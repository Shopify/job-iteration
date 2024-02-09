# frozen_string_literal: true

require "test_helper"

module JobIteration
  class TestHelperTest < ActiveSupport::TestCase
    include JobIteration::TestHelper

    class CounterJob < ActiveJob::Base
      include JobIteration::Iteration

      class << self
        attr_writer :count

        def count
          @count ||= 0
        end
      end

      def build_enumerator(times, cursor:)
        enumerator_builder.array(Array.new(times), cursor: cursor)
      end

      def each_iteration(_, _)
        self.class.count += 1
      end
    end

    teardown do
      CounterJob.count = nil
      ActiveJob::Base.queue_adapter.enqueued_jobs = []
    end

    test "#iterate_exact_times interrupts jobs after the given number of iterations" do
      iterate_exact_times(3.times)

      CounterJob.perform_now(10)

      assert_equal 3, CounterJob.count
    end

    test "#iterate_once interrupts jobs after a single iteration" do
      iterate_once

      CounterJob.perform_now(10)

      assert_equal 1, CounterJob.count
    end

    test "#continue_iterating allows jobs to iterate until the end" do
      iterate_exact_times(3.times)
      continue_iterating

      CounterJob.perform_now(10)

      assert_equal 10, CounterJob.count
    end

    test "#iterate_once allows jobs to run one iteration at a time" do
      iterate_once

      job = CounterJob.new(10)
      job.perform_now
      job.perform_now

      assert_equal 2, CounterJob.count
    end

    test "#continue_iterating allows the job to finish after running initial iterations" do
      iterate_once

      job = CounterJob.new(10)
      job.perform_now

      continue_iterating

      job.perform_now

      assert_equal 10, CounterJob.count
    end

    test "#mark_job_worker_as_interrupted marks the job as interrupted" do
      mark_job_worker_as_interrupted

      CounterJob.perform_now(10)

      # Since we only check if we should interrupt after each iteration, the job runs once.
      assert_equal 1, CounterJob.count
    end

    test "interruption can be triggered by the job itself" do
      test_context = self
      job_class = Class.new(CounterJob) do
        define_method(:each_iteration) do |*args|
          super(*args)

          test_context.mark_job_worker_as_interrupted
        end
      end

      job_class.perform_now(10)

      assert_equal 1, job_class.count
    end
  end
end
