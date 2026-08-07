# frozen_string_literal: true

begin
  require "shoryuken"
rescue LoadError
  # Shoryuken is not available, no need to load the adapter
  return
end

begin
  # Lifecycle event registration (Shoryuken.configure_server / config.on) was
  # introduced in Shoryuken 2.0.2.
  gem("shoryuken", ">= 2.0.2")
rescue Gem::LoadError
  warn("job-iteration's interruption adapter for Shoryuken requires Shoryuken 2.0.2 or newer")
  return
end

module JobIteration
  module InterruptionAdapters
    module ShoryukenAdapter
      class << self
        attr_accessor :stopping

        def call
          stopping
        end
      end

      Shoryuken.configure_server do |config|
        config.on(:shutdown) do
          ShoryukenAdapter.stopping = true
        end
      end
    end

    register(:shoryuken, ShoryukenAdapter)
  end
end
