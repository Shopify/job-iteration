# frozen_string_literal: true

require "test_helper"

require_relative "../support/jobs"
require_relative "integration_behaviour"

class ResqueIntegrationTest < ActiveSupport::TestCase
  include IntegrationBehaviour

  private

  def queue_adapter
    :resque
  end

  def start_worker_and_wait
    pid = nil
    Dir.chdir("test/support/resque") do
      pid = spawn(
        resque_env,
        "bundle exec rake resque:work",
        in: "/dev/null",
        out: "/dev/null",
        err: "/dev/null",
      )
    end
  ensure
    Process.wait(pid) if pid
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
