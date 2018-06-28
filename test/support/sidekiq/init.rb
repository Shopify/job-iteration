# frozen_string_literal: true

require 'job-iteration'
require 'active_job'
require 'i18n'

require_relative './worker'

I18n.available_locales = [:en]
ActiveJob::Base.queue_adapter = :sidekiq
