# frozen_string_literal: true

require "sidekiq"

module JobIteration
  module Integrations # @private
    module Sidekiq
      class << self
        attr_accessor :stopping

        def call
          stopping
        end
      end
    end

    JobIteration.interruption_adapter = JobIteration::Integrations::Sidekiq

    ::Sidekiq.configure_server do |config|
      config.on(:quiet) do
        JobIteration::Integrations::Sidekiq.stopping = true
      end
    end
  end
end
