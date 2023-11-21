# frozen_string_literal: true

module JobIteration
  module InterruptionAdapters
    # This adapter never interrupts.
    module NullAdapter
      class << self
        def call
          false
        end
      end
    end

    class << self
      # Returns adapter for specified name.
      #
      #   JobIteration::InterruptionAdapters.lookup(:sidekiq)
      #   # => JobIteration::InterruptionAdapters::SidekiqAdapter
      def lookup(name)
        registry.fetch(name.to_sym) do
          Deprecation.warn(<<~DEPRECATION_MESSAGE, caller_locations(1))
            No interruption adapter is registered for #{name.inspect}; falling back to `NullAdapter`, which never interrupts.
            See https://github.com/Shopify/job-iteration/blob/main/guides/???????? TBD
            This will raise starting in version #{Deprecation.deprecation_horizon} of #{Deprecation.gem_name}!"
          DEPRECATION_MESSAGE

          NullAdapter
        end
      end

      # Registers adapter for specified name.
      #
      #   JobIteration::InterruptionAdapters.register(:sidekiq, JobIteration::InterruptionAdapters::SidekiqAdapter)
      def register(name, adapter)
        raise ArgumentError, "adapter must be callable" unless adapter.respond_to?(:call)

        registry[name.to_sym] = adapter
      end

      private

      attr_reader :registry
    end

    @registry = {}

    Dir[File.join(__dir__, "interruption_adapters/*_adapter.rb")].each do |file|
      require file
    end
  end
end
