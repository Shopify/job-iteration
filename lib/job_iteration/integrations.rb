# frozen_string_literal: true

module JobIteration
  module Integrations
    IntegrationLoadError = Class.new(StandardError)

    extend ActiveSupport::Autoload

    autoload :SidekiqIntegration
    autoload :ResqueIntegration

    class << self
      def load(integration)
        integration = const_get(integration.to_s.camelize << "Integration")
        integration.new
      rescue NameError
        raise IntegrationLoadError, "#{integration} integration is not supported."
      end
    end
  end
end
