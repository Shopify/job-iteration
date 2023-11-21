# frozen_string_literal: true

require "job-iteration"

require "active_job"
require "i18n"

require_relative "../jobs"

Sidekiq.configure_server do |config|
  config.logger = nil
  config.redis = { host: ENV.fetch("REDIS_HOST", "localhost") }
end

I18n.available_locales = [:en]
ActiveJob::Base.queue_adapter = :sidekiq
