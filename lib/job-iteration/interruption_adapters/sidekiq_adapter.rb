# frozen_string_literal: true

require "sidekiq"

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
  end
end
