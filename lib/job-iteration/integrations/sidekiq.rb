# frozen_string_literal: true

require 'sidekiq'

module JobIteration
  module Integrations
    JobIteration.interruption_adapter = -> do
      if defined?(Sidekiq::CLI) && Sidekiq::CLI.instance
        Sidekiq::CLI.instance.launcher.stopping?
      else
        false
      end
    end
  end
end
