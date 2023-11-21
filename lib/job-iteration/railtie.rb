# frozen_string_literal: true

return unless defined?(Rails::Railtie)

module JobIteration
  class Railtie < Rails::Railtie
    initializer "job_iteration.register_deprecator" do |app|
      app.deprecators[:job_iteration] = JobIteration::Deprecation
    end
  end
end
