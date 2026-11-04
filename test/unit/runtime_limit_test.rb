# frozen_string_literal: true

require "test_helper"
require "sorbet-runtime"

module JobIteration
  class RuntimeLimitTest < IterationUnitTest
    include ActiveSupport::Testing::TimeHelpers

    class RuntimeLimitedJob < ActiveJob::Base
      include JobIteration::Iteration
      include ActiveSupport::Testing::TimeHelpers

      self.job_iteration_max_job_runtime = 3.seconds

      attr_reader :records, :events, :ensured

      on_start { events << :start }
      on_shutdown { events << :shutdown }
      on_complete { events << :complete }

      def build_enumerator(cursor:)
        @records = []
        @events = []
        @ensured = 0
        enumerator_builder.build_times_enumerator(5, cursor: cursor)
      end

      def each_iteration(record)
        travel(2.seconds)
        records << record
      ensure
        @ensured += 1
      end
    end

    class CompleteJob < RuntimeLimitedJob
      self.job_iteration_runtime_limit_behavior = :complete
    end

    class BooleanExitJob < CompleteJob
      extend T::Sig

      private

      sig { returns(T::Boolean) }
      def job_should_exit?
        !!super
      end
    end

    class CustomExitJob < CompleteJob
      private

      def job_should_exit?
        "max_job_runtime_exceeded"
      end
    end

    class SuppressedRuntimeExitJob < CompleteJob
      self.job_iteration_max_job_runtime = 1.second

      private

      def job_should_exit?
        @checks = (@checks || 0) + 1
        return (super && false) if @checks == 1

        true
      end
    end

    class FailingJob < CompleteJob
      self.job_iteration_max_job_runtime = 1.second

      def each_iteration(record)
        super
        raise "iteration failed"
      end
    end

    class ThrottledJob < CompleteJob
      self.job_iteration_max_job_runtime = 1.second

      def each_iteration(record)
        super
        throw(:abort, [:retry, 10.seconds])
      end
    end

    class ParallelCompleteJob < CompleteJob
      def build_enumerator(cursor:)
        super(cursor: nil)
        enumerator_builder.parallel(instances: 2, cursor: cursor) do |_, _, inner_cursor|
          enumerator_builder.build_times_enumerator(5, cursor: inner_cursor)
        end
      end
    end

    setup do
      freeze_time
      continue_iterating
      JobIteration.stubs(:max_job_runtime).returns(nil)
    end

    def test_default_behavior_resumes_with_the_saved_cursor
      assert_equal(:resume, RuntimeLimitedJob.job_iteration_runtime_limit_behavior)
      job = RuntimeLimitedJob.new
      job.perform_now

      assert_equal([0, 1], job.records)
      assert_equal([:start, :shutdown], job.events)
      continuation = enqueued_jobs.fetch(0)
      assert_equal(1, continuation.fetch("cursor_position"))
      assert_equal(1, continuation.fetch("times_interrupted"))
      assert_equal(4, continuation.fetch("total_time"))
    end

    def test_explicit_resume_preserves_the_runtime_interruption_reason
      job_class = Class.new(RuntimeLimitedJob) do
        self.job_iteration_runtime_limit_behavior = :resume
      end
      notifications = []
      callback = ->(event) { notifications << event.payload }

      ActiveSupport::Notifications.subscribed(callback, "interrupted.iteration") do
        job_class.perform_now
      end

      assert_equal("max_job_runtime_exceeded", notifications.fetch(0).fetch(:reason))
      assert_equal(1, enqueued_jobs.fetch(0).fetch("cursor_position"))
    end

    def test_runtime_completion_uses_normal_callbacks_and_instrumentation_without_retrying
      job = CompleteJob.new
      job.executions = 2
      notifications = []
      callback = ->(event) { notifications << event.name }
      job.expects(:retry_job).never

      ActiveSupport::Notifications.subscribed(callback, /(?:completed|interrupted)\.iteration/) do
        assert_nil(job.perform_now)
      end

      assert_equal([0, 1], job.records)
      assert_equal([:shutdown, :complete], job.events)
      assert_equal(3, job.executions)
      assert_equal(2, job.ensured)
      assert_equal(1, job.cursor_position)
      assert_equal(1, job.serialize.fetch("cursor_position"))
      assert_equal(0, job.times_interrupted)
      assert_equal(4, job.total_time)
      assert_equal(["completed.iteration"], notifications)
      assert_empty(enqueued_jobs)
    end

    def test_first_execution_runs_start_shutdown_and_complete_callbacks
      job = CompleteJob.new
      job.perform_now

      assert_equal([:start, :shutdown, :complete], job.events)
      assert_empty(enqueued_jobs)
    end

    def test_normal_enumerator_exhaustion_still_completes
      job_class = Class.new(CompleteJob) do
        self.job_iteration_max_job_runtime = 1.minute
      end
      job = job_class.new
      job.perform_now

      assert_equal([0, 1, 2, 3, 4], job.records)
      assert_equal([:start, :shutdown, :complete], job.events)
      assert_equal(4, job.cursor_position)
      assert_empty(enqueued_jobs)
    end

    def test_runtime_limit_keeps_the_existing_strict_greater_than_boundary
      job_class = Class.new(CompleteJob) do
        self.job_iteration_max_job_runtime = 4.seconds
      end
      job = job_class.new
      job.perform_now

      assert_equal([0, 1, 2], job.records)
      assert_equal(6, job.total_time)
      assert_empty(enqueued_jobs)
    end

    def test_completion_uses_the_lower_global_runtime_limit
      JobIteration.stubs(:max_job_runtime).returns(1.second)
      job = CompleteJob.new
      job.perform_now

      assert_equal([0], job.records)
      assert_equal([:start, :shutdown, :complete], job.events)
      assert_empty(enqueued_jobs)
    end

    def test_completion_without_a_runtime_limit_waits_for_exhaustion
      job_class = Class.new(CompleteJob) do
        self.job_iteration_max_job_runtime = nil
      end
      job = job_class.new
      job.perform_now

      assert_equal([0, 1, 2, 3, 4], job.records)
      assert_equal([:start, :shutdown, :complete], job.events)
      assert_empty(enqueued_jobs)
    end

    def test_early_adapter_shutdown_still_resumes
      mark_job_worker_as_interrupted
      job = CompleteJob.new
      job.perform_now

      assert_equal([0], job.records)
      assert_equal([:start, :shutdown], job.events)
      assert_equal(0, enqueued_jobs.fetch(0).fetch("cursor_position"))
    end

    def test_adapter_stop_is_not_reclassified_when_time_elapses_in_the_adapter
      adapter = -> {
        travel(10.seconds)
        "shutdown"
      }
      JobIteration.stubs(:interruption_adapter).returns(adapter)
      job = CompleteJob.new
      job.perform_now

      assert_equal([0], job.records)
      assert_equal([:start, :shutdown], job.events)
      assert_equal(0, enqueued_jobs.fetch(0).fetch("cursor_position"))
    end

    def test_runtime_retains_precedence_over_simultaneous_adapter_shutdown
      calls = 0
      adapter = -> { (calls += 1) > 1 }
      JobIteration.stubs(:interruption_adapter).returns(adapter)
      job = CompleteJob.new
      # The adapter would report shutdown at the second check, but runtime wins first.
      job.perform_now

      assert_equal(1, calls)
      assert_equal([0, 1], job.records)
      assert_equal([:start, :shutdown, :complete], job.events)
      assert_empty(enqueued_jobs)
    end

    def test_boolean_delegating_override_can_complete_at_the_runtime_limit
      job = BooleanExitJob.new
      job.perform_now

      assert_equal([0, 1], job.records)
      assert_equal([:start, :shutdown, :complete], job.events)
      assert_empty(enqueued_jobs)
    end

    def test_matching_custom_exit_string_does_not_imply_a_runtime_stop
      job = CustomExitJob.new
      job.perform_now

      assert_equal([0], job.records)
      assert_equal([:start, :shutdown], job.events)
      assert_equal(0, enqueued_jobs.fetch(0).fetch("cursor_position"))
    end

    def test_suppressed_runtime_stop_does_not_leak_into_a_later_custom_stop
      job = SuppressedRuntimeExitJob.new
      job.perform_now

      assert_equal([0, 1], job.records)
      assert_equal([:start, :shutdown], job.events)
      assert_equal(1, enqueued_jobs.fetch(0).fetch("cursor_position"))
    end

    def test_queue_wait_is_not_counted_as_runtime
      job = ActiveJob::Base.deserialize(CompleteJob.new.serialize)
      travel(1.hour)
      started_at = Time.now.utc
      job.perform_now

      assert_equal(started_at, job.start_time)
      assert_equal([0, 1], job.records)
      assert_equal(4, job.total_time)
      assert_empty(enqueued_jobs)
    end

    def test_resumed_execution_does_not_use_cumulative_runtime
      job = CompleteJob.new
      job.cursor_position = 0
      job.times_interrupted = 1
      job.total_time = 1000
      job.perform_now

      assert_equal([1, 2], job.records)
      assert_equal(2, job.cursor_position)
      assert_equal([:shutdown, :complete], job.events)
      assert_equal(1004, job.total_time)
      assert_equal(1, job.times_interrupted)
      assert_empty(enqueued_jobs)
    end

    def test_errors_are_not_converted_to_completion
      job = FailingJob.new
      error = assert_raises(RuntimeError) { job.perform_now }

      assert_equal("iteration failed", error.message)
      assert_equal([:start], job.events)
      assert_nil(job.cursor_position)
      assert_equal(2, job.total_time)
      assert_equal(1, job.ensured)
      assert_empty(enqueued_jobs)
    end

    def test_throttling_still_reenqueues_instead_of_completing
      job = ThrottledJob.new
      job.perform_now

      assert_equal([:start, :shutdown], job.events)
      assert_nil(enqueued_jobs.fetch(0).fetch("cursor_position"))
      assert_equal(1, job.times_interrupted)
    end

    def test_behavior_is_inherited_and_can_be_overridden_without_changing_the_parent
      child = Class.new(CompleteJob)
      sibling = Class.new(CompleteJob)
      assert_equal(:complete, child.job_iteration_runtime_limit_behavior)
      child.job_iteration_runtime_limit_behavior = :resume

      assert_equal(:resume, child.job_iteration_runtime_limit_behavior)
      assert_equal(:complete, sibling.job_iteration_runtime_limit_behavior)
      assert_equal(:complete, CompleteJob.job_iteration_runtime_limit_behavior)
      assert_equal(:resume, RuntimeLimitedJob.job_iteration_runtime_limit_behavior)
    end

    def test_invalid_behavior_raises_before_any_work
      [nil, false, "complete", :discard].each do |invalid|
        job_class = Class.new(RuntimeLimitedJob)
        job_class.job_iteration_runtime_limit_behavior = invalid
        job = job_class.new
        error = assert_raises(ArgumentError) { job.perform_now }

        assert_equal("job_iteration_runtime_limit_behavior must be :resume or :complete", error.message)
        assert_nil(job.records)
      end
      assert_empty(enqueued_jobs)
    end

    def test_parallel_root_fans_out_and_child_completes_with_its_cursor_identity
      root = ParallelCompleteJob.new
      root.perform_now
      assert_equal(2, enqueued_jobs.size)
      assert_empty(root.events)

      child = ActiveJob::Base.deserialize(enqueued_jobs.shift)
      child.perform_now

      assert_equal([0, 1], child.records)
      assert_equal([:start, :shutdown, :complete], child.events)
      expected_cursor = { "instance" => 0, "instances" => 2, "inner_cursor" => 1 }
      assert_equal(expected_cursor, child.cursor_position)
      assert_equal(expected_cursor, child.serialize.fetch("cursor_position"))
      assert_equal(0, child.times_interrupted)
      assert_equal(1, enqueued_jobs.size)
    end

    private

    def enqueued_jobs
      ActiveJob::Base.queue_adapter.enqueued_jobs
    end
  end
end
