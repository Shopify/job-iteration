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

require_relative "support/active_job_5_2_queue_adapters_test_adapter_compatibility_extension"

GlobalID.app = "iteration"
ActiveRecord::Base.include(GlobalID::Identification) # https://github.com/rails/globalid/blob/main/lib/global_id/railtie.rb

ActiveJob::Base.queue_adapter = :test

class Product < ActiveRecord::Base
  has_many :comments
end

class Comment < ActiveRecord::Base
  belongs_to :product
end

class TravelRoute < ActiveRecord::Base
  self.primary_key = [:origin, :destination]
end

class Order < ActiveRecord::Base
  self.primary_key = [:shop_id, :id]
end

mysql_host = ENV.fetch("MYSQL_HOST") { "localhost" }
mysql_port = ENV.fetch("MYSQL_PORT") { 3306 }

connection_config = {
  adapter: "mysql2",
  database: "job_iteration_test",
  username: "root",
  host: mysql_host,
  port: mysql_port,
}
connection_config[:password] = "root" if ENV["CI"]

ActiveRecord::Base.establish_connection(connection_config)

redis_url = ENV.fetch("REDIS_URL") { "redis://localhost:6379/0" }

Redis.singleton_class.class_eval do
  attr_accessor :current
end

Redis.current = Redis.new(url: redis_url, timeout: 1.0).tap(&:ping)
Resque.redis = Redis.current

Sidekiq.configure_client do |config|
  config.logger = nil
  config.redis = { url: redis_url }
end

ActiveRecord::Migration.suppress_messages do
  ActiveRecord::Schema.define do
    create_table(:products, force: true) do |t|
      t.string(:name)
      t.timestamps
    end

    create_table(:comments, force: true) do |t|
      t.string(:content)
      t.belongs_to(:product)
    end

    create_table(:travel_routes, force: true, primary_key: [:origin, :destination]) do |t|
      t.string(:destination)
      t.string(:origin)
    end

    create_table(:orders, force: true) do |t|
      t.integer(:shop_id)
      t.string(:name)
    end
  end
end

module LoggingHelpers
  def assert_logged(message)
    old_logger = JobIteration.logger
    log = StringIO.new
    JobIteration.logger = Logger.new(log)

    begin
      yield

      log.rewind
      assert_match(message, log.read)
    ensure
      JobIteration.logger = old_logger
    end
  end
end

module ActiveRecordHelpers
  def assert_sql(*patterns_to_match, &block)
    captured_queries = []
    assert_nothing_raised do
      ActiveSupport::Notifications.subscribed(
        ->(_name, _start_time, _end_time, _subscriber_id, payload) { captured_queries << payload[:sql] },
        "sql.active_record",
        &block
      )
    end

    failed_patterns = []
    patterns_to_match.each do |pattern|
      failed_check = captured_queries.none? do |sql|
        case pattern
        when Regexp
          sql.match?(pattern)
        when String
          sql == pattern
        else
          raise ArgumentError, "#assert_sql encountered an unknown matcher #{pattern.inspect}"
        end
      end
      failed_patterns << pattern if failed_check
    end
    queries = captured_queries.empty? ? "" : "\nQueries:\n  #{captured_queries.join("\n  ")}"
    assert_predicate(
      failed_patterns,
      :empty?,
      "Query pattern(s) #{failed_patterns.map(&:inspect).join(", ")} not found.#{queries}",
    )
  end
end

JobIteration.logger = Logger.new(IO::NULL)
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

  private

  def insert_fixtures
    now = Time.now
    10.times { |n| Product.create!(name: "lipstick #{n}", created_at: now - n, updated_at: now - n) }

    Product.order(:id).limit(3).map.with_index do |product, index|
      comments_count = index + 1
      comments_count.times.map { |n| { content: "#{product.name} comment ##{n}", product_id: product.id } }
    end.flatten.each do |comment|
      Comment.create!(**comment)
    end
  end

  def truncate_fixtures
    ActiveRecord::Base.connection.truncate(TravelRoute.table_name)
    ActiveRecord::Base.connection.truncate(Product.table_name)
    ActiveRecord::Base.connection.truncate(Comment.table_name)
  end

  def with_global_default_retry_backoff(backoff)
    original_default_retry_backoff = JobIteration.default_retry_backoff
    JobIteration.default_retry_backoff = backoff
    yield
  ensure
    JobIteration.default_retry_backoff = original_default_retry_backoff
  end
end
