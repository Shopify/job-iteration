# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../../lib", __FILE__)
require "minitest/autorun"

require "job-iteration"
require "job-iteration/test_helper"

require "sidekiq"
require "active_job"
require "active_record"
require "pry"
require 'mocha/minitest'
require 'database_cleaner'

module ActiveJob
  module QueueAdapters
    class IterationTestAdapter
      attr_writer(:enqueued_jobs)

      def enqueued_jobs
        @enqueued_jobs ||= []
      end

      def enqueue(job)
        enqueued_jobs << job.serialize
      end

      def enqueue_at(job, _delay)
        enqueued_jobs << job.serialize
      end
    end
  end
end

ActiveJob::Base.queue_adapter = :iteration_test

class Product < ActiveRecord::Base
end

ActiveRecord::Base.establish_connection adapter: "sqlite3", database: ":memory:"
ActiveRecord::Base.connection.create_table Product.table_name, force: true do |t|
  t.string :name
  t.timestamps
end

DatabaseCleaner.strategy = :truncation

module LoggingHelpers
  def assert_logged(message)
    old_logger = ActiveJob::Base.logger
    log = StringIO.new
    ActiveJob::Base.logger = log

    begin
      yield

      log.rewind
      assert_match message, log.read
    ensure
      ActiveJob::Base.logger = old_logger
    end
  end
end

ActiveJob::Base.logger = Logger.new(IO::NULL)

class ActiveSupport::TestCase
  include LoggingHelpers

  setup do
    insert_fixtures
  end

  teardown do
    ActiveJob::Base.queue_adapter.enqueued_jobs = []
    DatabaseCleaner.clean
  end

  def insert_fixtures
    10.times do |n|
      Product.create!(name: "lipstick #{n}")
    end
  end
end
