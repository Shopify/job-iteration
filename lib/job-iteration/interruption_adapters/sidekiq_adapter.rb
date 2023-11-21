# frozen_string_literal: true

begin
  require "sidekiq"
rescue LoadError
  return
end

module JobIteration
  module InterruptionAdapters
    module SidekiqAdapter
      class << self
        def call
          if defined?(Sidekiq::CLI) && Sidekiq::CLI.instance
            Sidekiq::CLI.instance.launcher.stopping?
          else
            false
          end
        end
      end
    end

    register(:sidekiq, SidekiqAdapter)
  end
end
