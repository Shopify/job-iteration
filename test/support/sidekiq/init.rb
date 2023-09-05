# frozen_string_literal: true

require "job-iteration"

require "active_job"
require "i18n"

require_relative "../jobs"

redis_host = if ENV["USING_DEV"] == "1"
  "job-iteration.railgun"
else
  "localhost"
end

Sidekiq.configure_server do |config|
  config.redis = { host: redis_host }
end

I18n.available_locales = [:en]
ActiveJob::Base.queue_adapter = :sidekiq
