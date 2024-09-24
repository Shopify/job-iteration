# frozen_string_literal: true

begin
  require "solid_queue"
rescue LoadError
  # SolidQueue is not available, no need to load the adapter
  return
end

begin
  # SolidQueue.on_worker_stop was introduced in SolidQueue 0.7.1
  gem("solid_queue", ">= 0.7.1")
rescue Gem::LoadError
  warn("job-iteration's interruption adapter for SolidQueue requires SolidQueue 0.7.1 or newer")
  return
end

module JobIteration
  module InterruptionAdapters
    module SolidQueueAdapter
      class << self
        attr_accessor :stopping

        def call
          stopping
        end
      end

      SolidQueue.on_worker_stop do
        SolidQueueAdapter.stopping = true
      end
    end

    register(:solid_queue, SolidQueueAdapter)
  end
end
