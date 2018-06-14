# frozen_string_literal: true

module JobIteration
  module TestHelper
    class StoppingSupervisor
      def initialize(stop_after_count)
        @stop_after_count = stop_after_count
        @calls = 0
      end

      def shutdown?
        @calls += 1
        (@calls % @stop_after_count) == 0
      end
    end

    private

    def iterate_exact_times(n_times, job:)
      job.any_instance.stubs(:job_should_exit?).returns(StoppingSupervisor.new(n_times.size))
    end

    def iterate_once(job:)
      iterate_exact_times(1.times)
    end

    def continue_iterating(job:)
      stub_supervisor_shutdown_to_return(false)
    end

    def mark_job_worker_as_interrupted(job:)
      stub_supervisor_shutdown_to_return(true)
    end

    def stub_supervisor_shutdown_to_return(value)
      fakesupervisor = mock
      fakesupervisor.stubs(shutdown?: value)
      job.any_instance.stubs(:job_should_exit?).returns(fakesupervisor)
    end

    def last_job_cursor(job_class)
      # enqueued_jobs
      jobs = jobs_in_queue(job_class.queue_name)
      assert_predicate jobs, :any?

      job = jobs.last
      assert_equal job_class.name, job.fetch("class")

      args = job.fetch("args")
      args[0].fetch("cursor_position")
    end
  end
end
