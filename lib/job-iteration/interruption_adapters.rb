# frozen_string_literal: true

module JobIteration
  module InterruptionAdapters
    AsyncAdapter = -> { false }
    InlineAdapter = -> { false }
    autoload :ResqueAdapter, "job-iteration/interruption_adapters/resque_adapter"
    autoload :SidekiqAdapter, "job-iteration/interruption_adapters/sidekiq_adapter"
    TestAdapter = -> { false }

    class << self
      # Returns adapter for specified name.
      #
      #   JobIteration::InterruptionAdapters.lookup(:sidekiq)
      #   # => JobIteration::InterruptionAdapters::SidekiqAdapter
      def lookup(name)
        const_get(name.to_s.camelize << "Adapter")
      rescue NameError
        # deprecation
        -> { false }
      end
    end
  end
end
