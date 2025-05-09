# frozen_string_literal: true

require "test_helper"
require "open3"

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
    _stdout, stderr, status = Open3.capture3(
      "bundle exec sidekiq -r ./test/support/sidekiq/init.rb -c 1",
    )

    assert_empty(stderr, "Sidekiq worker failed with:\n#{stderr}")
    assert_equal(status.exitstatus, 0)
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
