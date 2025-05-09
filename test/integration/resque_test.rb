# frozen_string_literal: true

require "test_helper"
require "open3"

require_relative "../support/jobs"
require_relative "integration_behaviour"

class ResqueIntegrationTest < ActiveSupport::TestCase
  include IntegrationBehaviour

  private

  def queue_adapter
    :resque
  end

  def start_worker_and_wait
    Dir.chdir("test/support/resque") do
      _stdout, stderr, status = Open3.capture3(
        resque_env,
        "bundle exec rake resque:work",
      )

      assert_empty(stderr, "Resque worker failed with:\n#{stderr}")
      assert_equal(status.exitstatus, 0)
    end
  end

  def resque_env
    {
      "QUEUE" => "default",
      "VVERBOSE" => "true",
      "VERBOSE" => "true",
      "GRACEFUL_TERM" => "true",
      "FORK_PER_JOB" => "false",
    }
  end

  def queue_size
    Resque.queue_sizes.fetch("default")
  end

  def job_args
    jobs_in_queue.first.fetch("args")
  end

  def jobs_in_queue
    Resque.redis.lrange("queue:default", 0, -1).map { |payload| JSON.parse(payload) }
  end

  def failed_job_error_class_name
    Resque::Failure.backend.all&.fetch("exception")
  end
end
