# frozen_string_literal: true

require_relative "./job-iteration/version"
require_relative "./job-iteration/enumerator_builder"
require_relative "./job-iteration/iteration"

module JobIteration
  IntegrationLoadError = Class.new(StandardError)

  INTEGRATIONS = [:resque, :sidekiq]

  Deprecation = ActiveSupport::Deprecation.new("2.0", "JobIteration")

  extend self

  # Use this to _always_ interrupt the job after it's been running for more than N seconds.
  # @example
  #
  #   JobIteration.max_job_runtime = 5.minutes
  #
  # This setting will make it to always interrupt a job after it's been iterating for 5 minutes.
  # Defaults to nil which means that jobs will not be interrupted except on termination signal.
  attr_accessor :max_job_runtime

  # Used internally for hooking into job processing frameworks like Sidekiq and Resque.
  attr_accessor :interruption_adapter
  self.interruption_adapter = -> { false }

  # Set if you want to use your own enumerator builder instead of default EnumeratorBuilder.
  # @example
  #
  #   class MyOwnBuilder < JobIteration::EnumeratorBuilder
  #     # ...
  #   end
  #
  #   JobIteration.enumerator_builder = MyOwnBuilder
  attr_accessor :enumerator_builder
  self.enumerator_builder = JobIteration::EnumeratorBuilder

  def load_integrations
    loaded = nil
    INTEGRATIONS.each do |integration|
      begin
        load_integration(integration)
        if loaded
          raise IntegrationLoadError,
            "#{loaded} integration has already been loaded, but #{integration} is also available. " \
            "Iteration will only work with one integration."
        end
        loaded = integration
      rescue LoadError
      end
    end
  end

  def load_integration(integration)
    unless INTEGRATIONS.include?(integration)
      raise IntegrationLoadError,
        "#{integration} integration is not supported. Available integrations: #{INTEGRATIONS.join(", ")}"
    end

    require_relative "./job-iteration/integrations/#{integration}"
  end
end

JobIteration.load_integrations unless ENV["ITERATION_DISABLE_AUTOCONFIGURE"]
