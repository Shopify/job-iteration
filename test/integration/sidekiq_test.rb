# frozen_string_literal: true

require "test_helper"

require "sidekiq/api"
require_relative "../support/jobs"

class SidekiqIntegrationTest < ActiveSupport::TestCase
  setup do
    @original_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :sidekiq
  end

  teardown do
    ActiveJob::Base.queue_adapter = @original_adapter
  end

  test "interrupts the job" do
    IterationJob.perform_later

    start_sidekiq_and_wait

    assert_equal 1, queue_size

    job_args = Sidekiq::Queue.new.first.args
    assert_equal 0, job_args.dig(0, "cursor_position")
    assert_equal 1, job_args.dig(0, "times_interrupted")

    start_sidekiq_and_wait

    assert_equal 1, queue_size
    job_args = Sidekiq::Queue.new.first.args
    assert_equal 2, job_args.dig(0, "cursor_position")
    assert_equal 2, job_args.dig(0, "times_interrupted")

    TerminateJob.perform_later
    start_sidekiq_and_wait

    assert_equal 0, queue_size
  end

  test "unserializable cursor corruption is prevented" do
    # Sidekiq serializes cursors as JSON, but not all objects are serializable.
    #     time   = Time.at(0).utc   # => 1970-01-01 00:00:00 UTC
    #     json   = JSON.dump(time)  # => "\"1970-01-01 00:00:00 UTC\""
    #     string = JSON.parse(json) # => "1970-01-01 00:00:00 UTC"
    # We serialized a Time, but it was deserialized as a String.
    TimeCursorJob.perform_later
    TerminateJob.perform_later
    start_sidekiq_and_wait

    assert_equal(
      JobIteration::Iteration::CursorError.name,
      failed_job_error_class_name,
    )
  end

  private

  def start_sidekiq_and_wait
    pid = spawn("bundle exec sidekiq -r ./test/support/sidekiq/init.rb -c 1")
  ensure
    Process.wait(pid)
  end

  def queue_size
    Sidekiq::Queue.new.size
  end

  def failed_job_error_class_name
    Sidekiq::RetrySet.new.first&.item&.fetch("error_class")
  end
end
