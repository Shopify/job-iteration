# frozen_string_literal: true

require "job-iteration"
require "job-iteration/integrations/sidekiq"

require "active_job"
require "i18n"

require_relative "../jobs"

redis_url = ENV.fetch("REDIS_URL") { "redis://localhost:6379/0" }

Sidekiq.configure_server do |config|
  config.logger = nil
  config.redis = { url: redis_url }
end

I18n.available_locales = [:en]
ActiveJob::Base.queue_adapter = :sidekiq
