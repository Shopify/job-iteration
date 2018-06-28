# frozen_string_literal: true

require 'test_helper'

require 'sidekiq/api'
require_relative '../support/sidekiq/worker'

class SidekiqIntegrationTest < ActiveSupport::TestCase
  setup do
    @original_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :sidekiq
    Sidekiq.redis do |conn|
      conn.flushdb
    end
  end

  teardown do
    ActiveJob::Base.queue_adapter = @original_adapter
  end

  test "inregrate" do
    MyWorker.perform_later

    start_sidekiq_and_wait

    assert_equal 1, Sidekiq::Queue.new.size

    job_args = Sidekiq::Queue.new.first.args
    assert_equal 0, job_args.dig(0, "cursor_position")
    assert_equal 1, job_args.dig(0, "times_interrupted")

    start_sidekiq_and_wait

    assert_equal 1, Sidekiq::Queue.new.size
    job_args = Sidekiq::Queue.new.first.args
    assert_equal 2, job_args.dig(0, "cursor_position")
    assert_equal 2, job_args.dig(0, "times_interrupted")

    TerminateWorker.perform_later
    start_sidekiq_and_wait

    assert_equal 0, Sidekiq::Queue.new.size
  end

  def start_sidekiq_and_wait
    pid = spawn("bundle exec sidekiq -r ./test/support/sidekiq/init.rb -c 1")
  ensure
    Process.wait(pid)
  end

end
