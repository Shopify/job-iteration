# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path("../../lib", __FILE__))
require "minitest/autorun"

ENV["ITERATION_DISABLE_AUTOCONFIGURE"] = "true"

require "job-iteration"
require "job-iteration/test_helper"

require "globalid"
require "sidekiq"
require "resque"
require "active_job"
require "active_record"
require "pry"
require "mocha/minitest"

GlobalID.app = "iteration"
ActiveRecord::Base.include(GlobalID::Identification) # https://github.com/rails/globalid/blob/main/lib/global_id/railtie.rb

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

host = ENV["USING_DEV"] == "1" ? "job-iteration.railgun" : "localhost"

connection_config = {
  adapter: "mysql2",
  database: "job_iteration_test",
  username: "root",
  host: host,
}
connection_config[:password] = "root" if ENV["CI"]

if ActiveRecord.respond_to?(:async_query_executor)
  ActiveRecord.async_query_executor = :global_thread_pool
end
ActiveRecord::Base.establish_connection(connection_config)

Redis.singleton_class.class_eval do
  attr_accessor :current
end

Redis.current = Redis.new(host: host, timeout: 1.0).tap(&:ping)

Resque.redis = Redis.current

Sidekiq.configure_client do |config|
  config.redis = { host: host }
end

ActiveRecord::Base.connection.create_table(Product.table_name, force: true) do |t|
  t.string(:name)
  t.timestamps
end

module LoggingHelpers
  def assert_logged(message)
    old_logger = ActiveJob::Base.logger
    log = StringIO.new
    ActiveJob::Base.logger = Logger.new(log)

    begin
      yield

      log.rewind
      assert_match(message, log.read)
    ensure
      ActiveJob::Base.logger = old_logger
    end
  end
end

ActiveJob::Base.logger = Logger.new(IO::NULL)

module ActiveSupport
  class TestCase
    setup do
      Redis.current.flushdb
    end

    def skip_until_version(version)
      skip("Deferred until version #{version}") if Gem::Version.new(JobIteration::VERSION) < Gem::Version.new(version)
    end
  end
end

class IterationUnitTest < ActiveSupport::TestCase
  include LoggingHelpers
  include JobIteration::TestHelper

  setup do
    insert_fixtures
  end

  teardown do
    ActiveJob::Base.queue_adapter.enqueued_jobs = []
    truncate_fixtures
  end

  def insert_fixtures
    10.times do |n|
      Product.create!(name: "lipstick #{n}")
    end
  end

  def truncate_fixtures
    ActiveRecord::Base.connection.truncate(Product.table_name)
  end
end
