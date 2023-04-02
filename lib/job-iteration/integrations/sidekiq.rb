# frozen_string_literal: true

module JobIteration
  module Integrations
    module Sidekiq
      class << self
        def call
          if defined?(::Sidekiq::CLI) && (instance = ::Sidekiq::CLI.instance)
            instance.launcher.stopping?
          else
            false
          end
        end
      end
    end
  end
end
