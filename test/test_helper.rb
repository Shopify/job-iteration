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
require "database_cleaner"

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

if defined?(ActiveRecord.queues) || defined?(ActiveRecord::Base.queues)
  class ApplicationJob < ::ActiveJob::Base
  end

  require "active_record/destroy_association_async_job"
  require "job-iteration/destroy_association_job"

  ActiveRecord::Base.destroy_association_async_job = JobIteration::DestroyAssociationJob

  class Product < ActiveRecord::Base
    has_many :variants, dependent: :destroy_async
  end

  class SoftDeletedProduct < ActiveRecord::Base
    self.table_name = "products"
    has_many :variants, foreign_key: "product_id", dependent: :destroy_async, ensuring_owner_was: :deleted?

    def deleted?
      deleted
    end

    def destroy
      update!(deleted: true)
      run_callbacks(:destroy)
      run_callbacks(:commit)
    end
  end
else
  class Product < ActiveRecord::Base
    has_many :variants, dependent: :destroy
  end
end

class Variant < ActiveRecord::Base
  belongs_to :product
end

host = ENV["USING_DEV"] == "1" ? "job-iteration.railgun" : "localhost"

connection_config = {
  adapter: "mysql2",
  database: "job_iteration_test",
  username: "root",
  host: host,
}
connection_config[:password] = "root" if ENV["CI"]

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
  t.string(:deleted, default: false)
  t.timestamps
end

ActiveRecord::Base.connection.create_table(Variant.table_name, force: true) do |t|
  t.references(:product)
  t.string(:color)
  t.timestamps
end

DatabaseCleaner.strategy = :truncation

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
    DatabaseCleaner.clean
  end

  def insert_fixtures
    10.times do |n|
      Product.create!(name: "lipstick #{n}")
    end
  end
end
