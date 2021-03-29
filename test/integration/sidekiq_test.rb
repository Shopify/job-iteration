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

  private

  def start_sidekiq_and_wait
    pid = spawn("bundle exec sidekiq -r ./test/support/sidekiq/init.rb -c 1")
  ensure
    Process.wait(pid)
  end

  def queue_size
    Sidekiq::Queue.new.size
  end
end
