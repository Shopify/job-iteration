# frozen_string_literal: true

require "sidekiq"

module JobIteration
  module Integrations
    class SidekiqIntegration
      def stopping?
        if defined?(Sidekiq::CLI) && Sidekiq::CLI.instance
          Sidekiq::CLI.instance.launcher.stopping?
        else
          false
        end
      end
    end
  end
end
