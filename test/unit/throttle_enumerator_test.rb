# typed: ignore
# frozen_string_literal: true

require "test_helper"

module JobIteration
  class ThrottleEnumeratorTest < IterationUnitTest
    class IterationThrottleJob < ActiveJob::Base
      include JobIteration::Iteration
      cattr_accessor :iterations_performed, instance_accessor: false
      self.iterations_performed = []

      cattr_accessor :on_complete_called, instance_accessor: false
      self.on_complete_called = 0
      cattr_accessor :on_reenqueue_called, instance_accessor: false
      self.on_reenqueue_called = 0

      cattr_accessor :should_throttle_sequence, instance_accessor: false
      self.should_throttle_sequence = []

      on_complete do
        self.class.on_complete_called += 1
      end

      on_reenqueue do
        self.class.on_reenqueue_called += 1
      end

      def build_enumerator(_params, cursor:)
        enumerator_builder.build_throttle_enumerator(
          enumerator_builder.build_array_enumerator(
            [1, 2, 3],
            cursor: cursor
          ),
          throttle_on: -> { IterationThrottleJob.should_throttle_sequence.shift },
          backoff: 30.seconds
        )
      end

      def each_iteration(record, _params)
        self.class.iterations_performed << record
      end
    end

    class IterationThrottleJobHaltReenqueue < IterationThrottleJob
      on_reenqueue do |_job|
        throw(:abort)
      end
    end

    setup do
      IterationThrottleJob.descendants.each do |klass|
        klass.iterations_performed = []
        klass.on_complete_called = 0
        klass.on_reenqueue_called = 0
      end
    end

    test "throttle enumerator proxies wrapped enumerator" do
      enum = enumerator_builder.array([1, 2, 3], cursor: nil)
      throttle_enum = enumerator_builder
        .throttle(
          enum,
          throttle_on: -> { false },
          backoff: 30.seconds
        )

      assert_equal enum.size, throttle_enum.size
      assert_equal enum.map { |e| e }, throttle_enum.map { |e| e }
    end

    test "yields value and a cursor with splat" do
      enum = enumerator_builder.build_throttle_enumerator(
        enumerator_builder.active_record_on_records(Product.all, cursor: nil),
        throttle_on: -> { false },
        backoff: 30.seconds
      )

      product = Product.all.first
      enum.each do |*args|
        assert_equal [product, product.id], args
        break
      end
    end

    test "throttle enumerator works with iteration API" do
      IterationThrottleJob.should_throttle_sequence = [false, false, false]

      IterationThrottleJob.perform_now({})

      assert_equal [1, 2, 3], IterationThrottleJob.iterations_performed
    end

    test "pushes job back to the queue if throttle" do
      IterationThrottleJob.should_throttle_sequence = [false, true, false]

      IterationThrottleJob.perform_now({})

      enqueued = ActiveJob::Base.queue_adapter.enqueued_jobs
      assert_equal 1, enqueued.size
      assert_equal 0, enqueued.first.fetch("cursor_position")

      assert_equal [1], IterationThrottleJob.iterations_performed
    end

    test "do not push back to queue if reenqueue callback abort" do
      IterationThrottleJobHaltReenqueue.should_throttle_sequence = [false, true, false]

      IterationThrottleJobHaltReenqueue.perform_now({})

      enqueued = ActiveJob::Base.queue_adapter.enqueued_jobs
      assert_equal 0, enqueued.size

      assert_equal [1], IterationThrottleJobHaltReenqueue.iterations_performed
    end

    test "does not pushed back to queue if not throttle" do
      assert_predicate ActiveJob::Base.queue_adapter.enqueued_jobs, :empty?

      IterationThrottleJob.should_throttle_sequence = [false, false, false]

      IterationThrottleJob.perform_now({})

      assert_predicate ActiveJob::Base.queue_adapter.enqueued_jobs, :empty?
      assert_equal [1, 2, 3], IterationThrottleJob.iterations_performed
    end

    test "does not execute on_complete callback if throttle" do
      IterationThrottleJob.should_throttle_sequence = [true]

      IterationThrottleJob.perform_now({})
      assert_equal 0, IterationThrottleJob.on_complete_called
    end

    test "throttle event is instrumented" do
      IterationThrottleJob.should_throttle_sequence = [true]

      called = false
      callback = ->(_event, _started, _finished, _job_id, args) {
        called = true
        assert_equal(IterationThrottleJob.name, args[:job_class])
      }
      ActiveSupport::Notifications.subscribed(callback, "throttled.iteration") do
        IterationThrottleJob.perform_now({})
      end
      assert called
    end

    private

    def enumerator_builder
      JobIteration::EnumeratorBuilder.new(nil)
    end
  end
end
