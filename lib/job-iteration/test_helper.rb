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

    def iterate_exact_times(n_times)
      JobIteration.stubs(:interruption_adapter).returns(StoppingSupervisor.new(n_times.size))
    end

    def iterate_once
      iterate_exact_times(1.times)
    end

    def continue_iterating
      stub_shutdown_adapter_to_return(false)
    end

    def mark_job_worker_as_interrupted
      stub_shutdown_adapter_to_return(true)
    end

    def stub_shutdown_adapter_to_return(value)
      adapter = mock.stubs(shutdown?: false)
      JobIteration.stubs(:interruption_adapter).returns(adapter)
    end
  end
end
