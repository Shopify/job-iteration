# frozen_string_literal: true

module JobIteration
  # @api private
  module Integrations
    LoadError = Class.new(StandardError)

    extend self

    attr_accessor :registered_integrations

    self.registered_integrations = {}

    autoload :Sidekiq, "job-iteration/integrations/sidekiq"
    autoload :Resque, "job-iteration/integrations/resque"

    # @api public
    def register(name, callable)
      raise ArgumentError, "Interruption adapter must respond to #call" unless callable.respond_to?(:call)

      registered_integrations[name] = callable
    end

    def load(name)
      if (callable = registered_integrations[name])
        callable
      else
        begin
          klass = "#{self}::#{name.camelize}".constantize
          register(name, klass)
        rescue NameError
          raise LoadError, "Could not find integration for '#{name}'"
        end
      end
    end
  end
end
