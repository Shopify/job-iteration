# frozen_string_literal: true

module JobIteration
  # Include JobIteration::TestHelper to mock interruption when testing your jobs.
  module TestHelper
    class StoppingSupervisor # @private
      def initialize(stop_after_count)
        @stop_after_count = stop_after_count
        @calls = 0
      end

      def call
        @calls += 1
        (@calls % @stop_after_count) == 0
      end
    end

    # Stubs interruption adapter to interrupt the job after every N iterations.
    # @param [Integer] n_times Number of times before the job is interrupted
    # @example
    #   test "this stuff interrupts" do
    #     iterate_exact_times(3.times)
    #     MyJob.perform_now
    #   end
    def iterate_exact_times(n_times)
      JobIteration::Integrations.stubs(:load).returns(StoppingSupervisor.new(n_times.size))
    end

    # Stubs interruption adapter to interrupt the job after every sing iteration.
    # @see #iterate_exact_times
    def iterate_once
      iterate_exact_times(1.times)
    end

    # Removes previous stubs and tells the job to iterate until the end.
    def continue_iterating
      stub_shutdown_adapter_to_return(false)
    end

    # Stubs the worker as already interrupted.
    def mark_job_worker_as_interrupted
      stub_shutdown_adapter_to_return(true)
    end

    private

    def stub_shutdown_adapter_to_return(value)
      adapter = mock
      adapter.stubs(:call).returns(value)
      JobIteration::Integrations.stubs(:load).returns(adapter)
    end
  end
end
