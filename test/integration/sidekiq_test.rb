# frozen_string_literal: true

require "test_helper"

require "sidekiq/api"
require "sidekiq/rails"
require_relative "../support/jobs"
require_relative "integration_behaviour"

class SidekiqIntegrationTest < ActiveSupport::TestCase
  include IntegrationBehaviour

  private

  def queue_adapter
    :sidekiq
  end

  def start_worker_and_wait
    pid = spawn(
      "bundle exec sidekiq -r ./test/support/sidekiq/init.rb -c 1",
      in: "/dev/null",
      out: "/dev/null",
      err: "/dev/null",
    )
  ensure
    Process.wait(pid)
  end

  def queue_size
    Sidekiq::Queue.new.size
  end

  def job_args
    Sidekiq::Queue.new.first.args
  end

  def failed_job_error_class_name
    Sidekiq::RetrySet.new.first&.item&.fetch("error_class")
  end
end
