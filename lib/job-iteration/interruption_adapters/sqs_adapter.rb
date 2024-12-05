# frozen_string_literal: true

begin
  require "aws-activejob-sqs"
rescue LoadError
  # Aws::ActiveJob::SQS is not available, no need to load the adapter
  return
end

begin
  # Aws::ActiveJob::SQS.on_worker_stop was introduced in Aws::ActiveJob::SQS 0.1.1
  gem("aws-activejob-sqs", ">= 0.1.1")
rescue Gem::LoadError
  warn("job-iteration's interruption adapter for SQS requires aws-activejob-sqs 0.1.1 or newer")
  return
end

module JobIteration
  module InterruptionAdapters
    module SqsAdapter
      class << self
        attr_accessor :stopping

        def call
          stopping
        end
      end

      Aws::ActiveJob::SQS.on_worker_stop do
        SqsAdapter.stopping = true
      end
    end

    register(:sqs, SqsAdapter)
  end
end
