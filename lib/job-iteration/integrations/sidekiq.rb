# frozen_string_literal: true

require 'sidekiq'

module JobIteration
  module Integrations
    module SidekiqInterruptionAdapter
      extend self

      def shutdown?
        if defined?(Sidekiq::CLI) && Sidekiq::CLI.instance
          Sidekiq::CLI.instance.launcher.stopping?
        else
          false
        end
      end
    end

    JobIteration.interruption_adapter = SidekiqInterruptionAdapter
  end
end
