# typed: ignore
# frozen_string_literal: true

require "test_helper"

module JobIteration
  class ParallelEnumeratorTest < IterationUnitTest
    INSTANCES = 3

    class IterationParallelJob < ActiveJob::Base
      include JobIteration::Iteration

      cattr_accessor :iterations_performed, instance_accessor: false
      self.iterations_performed = []

      cattr_accessor :on_start_called, instance_accessor: false
      self.on_start_called = 0

      cattr_accessor :on_shutdown_called, instance_accessor: false
      self.on_shutdown_called = 0

      cattr_accessor :on_complete_called, instance_accessor: false
      self.on_complete_called = 0

      on_start do
        self.class.on_start_called += 1
      end

      on_shutdown do
        self.class.on_shutdown_called += 1
      end

      on_complete do
        self.class.on_complete_called += 1
      end

      def build_enumerator(_params, cursor:)
        enumerator_builder.parallel(instances: INSTANCES, cursor: cursor) do |instance, instances, inner_cursor|
          records = (instance..9).step(instances).to_a
          enumerator_builder.build_array_enumerator(records, cursor: inner_cursor)
        end
      end

      def each_iteration(record, _params)
        self.class.iterations_performed << record
      end
    end

    setup do
      IterationParallelJob.iterations_performed = []
      IterationParallelJob.on_start_called = 0
      IterationParallelJob.on_shutdown_called = 0
      IterationParallelJob.on_complete_called = 0
    end

    test "build_parallel_enumerator raises ArgumentError when instances is not a positive Integer" do
      [0, -1, nil, 3.5, "3"].each do |bad_value|
        error = assert_raises(ArgumentError, "expected ArgumentError for instances: #{bad_value.inspect}") do
          enumerator_builder.build_parallel_enumerator(instances: bad_value, cursor: nil) { |_, _, _| [] }
        end
        assert_equal("instances must be a positive Integer", error.message)
      end
    end

    test "build_parallel_enumerator returns EnqueueJobs when cursor is nil" do
      result = enumerator_builder.build_parallel_enumerator(instances: 3, cursor: nil) { |_, _, _| [] }
      assert_instance_of(ParallelEnumerator::EnqueueJobs, result)
    end

    test "build_parallel_enumerator does not invoke the block when cursor is nil" do
      called = false
      enumerator_builder.build_parallel_enumerator(instances: 3, cursor: nil) do |_, _, _|
        called = true
        []
      end
      refute(called)
    end

    test "build_parallel_enumerator returns a wrapped enumerator when cursor is given" do
      enum = enumerator_builder.build_parallel_enumerator(
        instances: 2,
        cursor: { "instance" => 0, "inner_cursor" => nil },
      ) do |_, _, inner_cursor|
        enumerator_builder.build_array_enumerator([1, 2, 3], cursor: inner_cursor)
      end

      assert_kind_of(EnumeratorBuilder::Wrapper, enum)
    end

    test "ParallelEnumerator passes instance, instances, and inner_cursor to the block" do
      received = []
      block = ->(instance, instances, inner_cursor) {
        received << [instance, instances, inner_cursor]
        [].each
      }

      ParallelEnumerator.new(block, instances: 4, cursor: { "instance" => 2, "inner_cursor" => "abc" })

      assert_equal([[2, 4, "abc"]], received)
    end

    test "ParallelEnumerator yields each value with a parallel cursor wrapping the inner cursor" do
      block = ->(_instance, _instances, inner_cursor) {
        enumerator_builder.build_array_enumerator(["a", "b", "c"], cursor: inner_cursor)
      }
      enum = ParallelEnumerator.new(block, instances: 2, cursor: { "instance" => 1, "inner_cursor" => nil }).to_enum

      yielded = enum.to_a

      assert_equal(
        [
          ["a", { "instance" => 1, "inner_cursor" => 0 }],
          ["b", { "instance" => 1, "inner_cursor" => 1 }],
          ["c", { "instance" => 1, "inner_cursor" => 2 }],
        ],
        yielded,
      )
    end

    test "ParallelEnumerator resumes iteration from the inner cursor" do
      block = ->(_instance, _instances, inner_cursor) {
        enumerator_builder.build_array_enumerator(["a", "b", "c"], cursor: inner_cursor)
      }
      enum = ParallelEnumerator.new(block, instances: 2, cursor: { "instance" => 0, "inner_cursor" => 0 }).to_enum

      assert_equal(
        [
          ["b", { "instance" => 0, "inner_cursor" => 1 }],
          ["c", { "instance" => 0, "inner_cursor" => 2 }],
        ],
        enum.to_a,
      )
    end

    test "ParallelEnumerator size delegates to the inner enumerator" do
      block = ->(_instance, _instances, inner_cursor) {
        enumerator_builder.build_array_enumerator([1, 2, 3, 4, 5], cursor: inner_cursor)
      }
      enum = ParallelEnumerator.new(block, instances: 2, cursor: { "instance" => 0, "inner_cursor" => nil }).to_enum

      assert_equal(5, enum.size)
    end

    test "iteration with parallel enumerator enqueues one job per instance when cursor is nil" do
      IterationParallelJob.perform_now({})

      enqueued = ActiveJob::Base.queue_adapter.enqueued_jobs
      assert_equal(INSTANCES, enqueued.size)

      cursor_positions = enqueued.map { |job| job.fetch("cursor_position") }
      assert_equal(
        INSTANCES.times.map { |i| { "instance" => i, "inner_cursor" => nil } },
        cursor_positions,
      )
    end

    test "iteration with parallel enumerator enqueues jobs of the same class as the calling job" do
      IterationParallelJob.perform_now({})

      enqueued = ActiveJob::Base.queue_adapter.enqueued_jobs
      job_classes = enqueued.map { |job| job.fetch("job_class") }
      assert_equal([IterationParallelJob.name] * INSTANCES, job_classes)
    end

    test "iteration with parallel enumerator forwards arguments to enqueued jobs" do
      params = { "shop_id" => 42 }
      IterationParallelJob.perform_now(params)

      enqueued = ActiveJob::Base.queue_adapter.enqueued_jobs
      assert_equal(INSTANCES, enqueued.size)
      enqueued.each do |job|
        deserialized_arguments = ActiveJob::Arguments.deserialize(job.fetch("arguments"))
        assert_equal([params], deserialized_arguments)
      end
    end

    test "iteration with parallel enumerator forwards parent queue_name and priority overrides to enqueued jobs" do
      job = IterationParallelJob.new({})
      job.queue_name = "custom_queue"
      job.priority = 10
      job.perform_now

      enqueued = ActiveJob::Base.queue_adapter.enqueued_jobs
      assert_equal(INSTANCES, enqueued.size)
      enqueued.each do |child|
        assert_equal("custom_queue", child.fetch("queue_name"))
        assert_equal(10, child.fetch("priority"))
      end
    end

    test "iteration with parallel enumerator raises EnqueueError if any child job fails to enqueue" do
      IterationParallelJob.any_instance.stubs(:successfully_enqueued?).returns(false)

      assert_raises(ParallelEnumerator::EnqueueError) do
        IterationParallelJob.perform_now({})
      end
    end

    test "enqueue_parallel_jobs event is instrumented" do
      called = false
      callback = ->(_event, _started, _finished, _job_id, payload) {
        called = true
        assert_equal(IterationParallelJob.name, payload[:job_class])
        assert_equal(INSTANCES, payload[:instances])
      }
      ActiveSupport::Notifications.subscribed(callback, "enqueue_parallel_jobs.iteration") do
        IterationParallelJob.perform_now({})
      end
      assert(called)
    end

    test "iteration with parallel enumerator does not iterate or run iteration callbacks on the parent job" do
      IterationParallelJob.perform_now({})

      assert_empty(IterationParallelJob.iterations_performed)
      assert_equal(0, IterationParallelJob.on_start_called)
      assert_equal(0, IterationParallelJob.on_shutdown_called)
      assert_equal(0, IterationParallelJob.on_complete_called)
    end

    test "iteration with parallel enumerator runs iteration callbacks on the child job" do
      job = IterationParallelJob.new({})
      job.cursor_position = { "instance" => 1, "inner_cursor" => nil }
      job.perform_now

      assert_equal([1, 4, 7], IterationParallelJob.iterations_performed)
      assert_predicate(ActiveJob::Base.queue_adapter.enqueued_jobs, :empty?)
      assert_equal(1, IterationParallelJob.on_start_called)
      assert_equal(1, IterationParallelJob.on_shutdown_called)
      assert_equal(1, IterationParallelJob.on_complete_called)
    end

    test "iteration with parallel enumerator updates cursor_position with the parallel cursor" do
      job = IterationParallelJob.new({})
      job.cursor_position = { "instance" => 2, "inner_cursor" => nil }
      job.perform_now

      assert_equal({ "instance" => 2, "inner_cursor" => 2 }, job.cursor_position)
    end

    private

    def enumerator_builder
      JobIteration::EnumeratorBuilder.new(nil)
    end
  end
end
