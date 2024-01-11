# frozen_string_literal: true

begin
  require "sidekiq"
rescue LoadError
  # Sidekiq is not available, no need to load the adapter
  return
end

module JobIteration
  module InterruptionAdapters
    module SidekiqAdapter
      class << self
        attr_accessor :stopping

        def call
          stopping
        end
      end

      ::Sidekiq.configure_server do |config|
        config.on(:quiet) do
          SidekiqAdapter.stopping = true
        end
      end
    end

    register(:sidekiq, SidekiqAdapter)
  end
end
