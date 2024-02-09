# frozen_string_literal: true

return unless defined?(Rails::Railtie)

module JobIteration
  class Railtie < Rails::Railtie
    initializer "job_iteration.register_deprecator" do |app|
      # app.deprecators was added in Rails 7.1
      app.deprecators[:job_iteration] = JobIteration::Deprecation if app.respond_to?(:deprecators)
    end
  end
end
