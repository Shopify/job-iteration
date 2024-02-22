# frozen_string_literal: true

begin
  require "good_job"
rescue LoadError
  # GoodJob is not available, no need to load the adapter
  return
end

module JobIteration
  module InterruptionAdapters
    module GoodJobAdapter
      class << self
        attr_accessor :stopping

        def call
          stopping
        end
      end

      ActiveSupport::Notifications.subscribe("scheduler_shutdown_start.good_job") do
        GoodJobAdapter.stopping = true
      end
    end

    register(:good_job, GoodJobAdapter)
  end
end
