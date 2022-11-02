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
  has_many :comments
end

class Comment < ActiveRecord::Base
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

ActiveRecord::Schema.define do
  create_table(:products, force: true) do |t|
    t.string(:name)
    t.timestamps
  end

  create_table(:comments, force: true) do |t|
    t.string(:content)
    t.belongs_to(:product)
  end
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
    now = Time.now
    products = 10.times.map { |n| { name: "lipstick #{n}", created_at: now - n, updated_at: now - n } }
    Product.insert_all!(products)

    comments = Product.order(:id).limit(3).map.with_index do |product, index|
      comments_count = index + 1
      comments_count.times.map { |n| { content: "#{product.name} comment ##{n}", product_id: product.id } }
    end.flatten

    Comment.insert_all!(comments)
  end

  def truncate_fixtures
    ActiveRecord::Base.connection.truncate(Product.table_name)
  end
end
