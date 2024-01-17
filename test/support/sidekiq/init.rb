# frozen_string_literal: true

require "job-iteration"
require "job-iteration/integrations/sidekiq"

require "active_job"
require "i18n"

require_relative "../jobs"

redis_host = ENV.fetch("REDIS_HOST") { "localhost" }
redis_port = ENV.fetch("REDIS_PORT") { 6379 }

Sidekiq.configure_server do |config|
  config.redis = { host: redis_host, port: redis_port }
end

I18n.available_locales = [:en]
ActiveJob::Base.queue_adapter = :sidekiq
