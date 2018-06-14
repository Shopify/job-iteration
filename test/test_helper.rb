# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../../lib", __FILE__)
require "minitest/autorun"

require "sidekiq"
require "job-iteration"
require "job-iteration/test_helper"
require "active_job"
require "active_record"
require "pry"
require 'mocha/minitest'

ActiveJob::Base.logger = Logger.new(STDOUT)

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

      def enqueue_at(*)
        raise NotImplementedError
      end
    end
  end
end

ActiveJob::Base.queue_adapter = :iteration_test

class Post < ActiveRecord::Base
end

class Minitest::Test
  def setup
    insert_fixtures
    super
  end

  def teardown
    ActiveRecord::Base.connection.disconnect!
  end

  def insert_fixtures
    ActiveRecord::Base.establish_connection adapter: "sqlite3", database: ":memory:"
    ActiveRecord::Base.connection.create_table :posts, force: true do |t|
      t.string :name
      t.timestamps
    end
    %w(first second third last).each { |name| Post.create!(name: name) }
  end
end
