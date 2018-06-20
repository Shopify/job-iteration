# frozen_string_literal: true

require 'sidekiq'

module JobIteration
  module Integrations
    module Sidekiq
      def job_should_exit?
        if defined?(Sidekiq::CLI) && Sidekiq::CLI.instance
          Sidekiq::CLI.instance.launcher.stopping?
        else
          false
        end
      end
    end
  end
end

Sidekiq::Worker.prepend(JobIteration::Integrations::Sidekiq)
