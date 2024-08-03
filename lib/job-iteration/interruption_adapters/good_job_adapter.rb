# frozen_string_literal: true

begin
  require "good_job"
rescue LoadError
  # GoodJob is not available, no need to load the adapter
  return
end

begin
  # GoodJob.current_thread_shutting_down? was introduced in GoodJob 3.26
  gem("good_job", ">= 3.26")
rescue Gem::LoadError
  warn("job-iteration's interruption adapter for GoodJob requires GoodJob 3.26 or newer")
  return
end

module JobIteration
  module InterruptionAdapters
    module GoodJobAdapter
      class << self
        def call
          !!::GoodJob.current_thread_shutting_down?
        end
      end
    end

    register(:good_job, GoodJobAdapter)
  end
end
