# frozen_string_literal: true

begin
  require "delayed_job"
rescue LoadError
  # DelayedJobb is not available, no need to load the adapter
  return
end

begin
  # Delayed::Worker#stop? was introduced in DelayedJob 3.0.3
  gem("delayed_job", ">= 3.0.3")
rescue Gem::LoadError
  warn("job-iteration's interruption adapter for DelayedJob requires DelayedJob 3.0.3 or newer")
  return
end

module JobIteration
  module InterruptionAdapters
    module DelayedJobAdapter
      class << self
        attr_accessor :delayed_worker, :delayed_worker_started

        def call
          if delayed_worker_started
            delayed_worker.nil? || delayed_worker.stop?
          else
            false
          end
        end
      end

      self.delayed_worker_started = false

      class DelayedJobPlugin < Delayed::Plugin
        callbacks do |lifecycle|
          lifecycle.before(:execute) do |worker|
            DelayedJobAdapter.delayed_worker = worker
            DelayedJobAdapter.delayed_worker_started = true
          end

          lifecycle.after(:execute) do |_worker|
            DelayedJobAdapter.delayed_worker = nil
          end
        end
      end
      private_constant :DelayedJobPlugin

      Delayed::Worker.plugins << DelayedJobPlugin
    end

    register(:delayed_job, DelayedJobAdapter)
  end
end
