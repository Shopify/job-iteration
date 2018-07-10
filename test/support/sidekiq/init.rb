# frozen_string_literal: true

require 'job-iteration'
require 'job-iteration/integrations/sidekiq'

require 'active_job'
require 'i18n'

require_relative '../jobs'

I18n.available_locales = [:en]
ActiveJob::Base.queue_adapter = :sidekiq
