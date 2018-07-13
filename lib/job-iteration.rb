# frozen_string_literal: true

require_relative "./job-iteration/version"
require_relative "./job-iteration/enumerator_builder"
require_relative "./job-iteration/iteration"

module JobIteration
  IntegrationLoadError = Class.new(StandardError)

  INTEGRATIONS = [:resque, :sidekiq]

  extend self

  attr_accessor :max_job_runtime, :interruption_adapter
  self.interruption_adapter = -> { false }

  def load_integrations
    loaded = nil
    INTEGRATIONS.each do |integration|
      if loaded
        raise IntegrationLoadError,
          "#{loaded} integration has already been loaded, but #{integration} is also available. " \
          "Iteration will only work with one integration."
      end

      begin
        load_integration(integration)
        loaded = integration
      rescue LoadError
      end
    end
  end

  def load_integration(integration)
    unless INTEGRATIONS.include?(integration)
      raise IntegrationLoadError,
        "#{integration} integration is not supported. Available integrations: #{INTEGRATIONS.join(', ')}"
    end

    require_relative "./job-iteration/integrations/#{integration}"
  end
end

JobIteration.load_integrations unless ENV['ITERATION_DISABLE_AUTOCONFIGURE']
