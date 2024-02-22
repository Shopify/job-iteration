# frozen_string_literal: true

require_relative "interruption_adapters/null_adapter"

module JobIteration
  module InterruptionAdapters
    BUNDLED_ADAPTERS = [:good_job, :resque, :sidekiq].freeze # @api private

    class << self
      # Returns adapter for specified name.
      #
      #   JobIteration::InterruptionAdapters.lookup(:sidekiq)
      #   # => JobIteration::InterruptionAdapters::SidekiqAdapter
      def lookup(name)
        registry.fetch(name.to_sym) do
          Deprecation.warn(<<~DEPRECATION_MESSAGE, caller_locations(1))
            No interruption adapter is registered for #{name.inspect}; falling back to `NullAdapter`, which never interrupts.
            Use `JobIteration::InterruptionAdapters.register(#{name.to_sym.inspect}, <adapter>) to register one.
            This will raise starting in version #{Deprecation.deprecation_horizon} of #{Deprecation.gem_name}!"
          DEPRECATION_MESSAGE

          NullAdapter
        end
      end

      # Registers adapter for specified name.
      #
      #   JobIteration::InterruptionAdapters.register(:sidekiq, MyCustomSidekiqAdapter)
      def register(name, adapter)
        raise ArgumentError, "adapter must be callable" unless adapter.respond_to?(:call)

        registry[name.to_sym] = adapter
      end

      private

      attr_reader :registry
    end

    @registry = {}

    # Built-in Rails adapters. It doesn't make sense to interrupt for these.
    register(:async, NullAdapter)
    register(:inline, NullAdapter)
    register(:test, NullAdapter)

    # External adapters
    BUNDLED_ADAPTERS.each do |name|
      require_relative "interruption_adapters/#{name}_adapter"
    end
  end
end
