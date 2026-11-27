# typed: ignore
# frozen_string_literal: true

require "test_helper"

module JobIteration
  class ThrottleEnumeratorTest < IterationUnitTest
    include ActiveSupport::Testing::TimeHelpers

    class IterationThrottleJob < ActiveJob::Base
      include JobIteration::Iteration
      cattr_accessor :iterations_performed, instance_accessor: false
      self.iterations_performed = []

      cattr_accessor :on_complete_called, instance_accessor: false
      self.on_complete_called = 0

      cattr_accessor :should_throttle_sequence, instance_accessor: false
      self.should_throttle_sequence = []

      on_complete do
        self.class.on_complete_called += 1
      end

      def build_enumerator(_params, cursor:)
        enumerator_builder.build_throttle_enumerator(
          enumerator_builder.build_array_enumerator(
            [1, 2, 3],
            cursor: cursor,
          ),
          throttle_on: -> { IterationThrottleJob.should_throttle_sequence.shift },
          backoff: 30.seconds,
        )
      end

      def each_iteration(record, _params)
        self.class.iterations_performed << record
      end
    end

    class CustomizableThrottleJob < ActiveJob::Base
      include JobIteration::Iteration

      def build_enumerator(params, cursor:)
        enumerator_builder.build_throttle_enumerator(
          params.fetch(:enumerator),
          throttle_on: params.fetch(:throttle_on),
          backoff: params.fetch(:backoff, 30.seconds),
        )
      end

      def each_iteration(_record, _params); end
    end

    # Records, in order, every throttle check, every query against `products` made by the enumerator, and every
    # processed item, so tests can pin down when the throttle runs relative to the fetch.
    class ActiveRecordThrottleJob < ActiveJob::Base
      include JobIteration::Iteration

      cattr_accessor :builder_method, instance_accessor: false
      cattr_accessor :check_before_fetch, instance_accessor: false
      cattr_accessor :throttle_sequence, instance_accessor: false
      cattr_accessor :events, instance_accessor: false
      cattr_accessor :processed_ids, instance_accessor: false
      cattr_accessor :on_complete_called, instance_accessor: false

      on_complete do
        self.class.on_complete_called += 1
      end

      def build_enumerator(cursor:)
        enumerator_builder.build_throttle_enumerator(
          enumerator_builder.public_send(self.class.builder_method, Product.all, cursor: cursor, batch_size: 3),
          throttle_on: -> {
            self.class.events << :check
            self.class.throttle_sequence.shift || false
          },
          backoff: 30.seconds,
          check_before_fetch: self.class.check_before_fetch,
        )
      end

      def each_iteration(item)
        ids = ThrottleEnumeratorTest.untracked do
          case item
          when Product then [item.id]
          when Array then item.map(&:id)
          else item.pluck(:id) # an Active Record relation from active_record_on_batch_relations
          end
        end
        self.class.events << :process
        self.class.processed_ids.concat(ids)
      end
    end

    class StackedThrottleJob < ActiveJob::Base
      include JobIteration::Iteration

      cattr_accessor :check_before_fetch, instance_accessor: false
      cattr_accessor :events, instance_accessor: false

      def build_enumerator(cursor:)
        inner = enumerator_builder.build_throttle_enumerator(
          enumerator_builder.active_record_on_batches(Product.all, cursor: cursor, batch_size: 5),
          throttle_on: -> {
            self.class.events << :inner
            false
          },
          backoff: 30.seconds,
          check_before_fetch: self.class.check_before_fetch,
        )
        enumerator_builder.build_throttle_enumerator(
          inner,
          throttle_on: -> {
            self.class.events << :outer
            false
          },
          backoff: 30.seconds,
          check_before_fetch: self.class.check_before_fetch,
        )
      end

      def each_iteration(_batch)
        self.class.events << :process
      end
    end

    class NestedThrottleJob < ActiveJob::Base
      include JobIteration::Iteration

      cattr_accessor :throttle_sequence, instance_accessor: false
      cattr_accessor :events, instance_accessor: false
      cattr_accessor :processed_ids, instance_accessor: false

      def build_enumerator(cursor:)
        enumerator_builder.build_throttle_enumerator(
          enumerator_builder.nested(
            [
              ->(cursor) { enumerator_builder.active_record_on_records(Product.where(id: Comment.select(:product_id)), cursor: cursor) },
              ->(product, cursor) { enumerator_builder.active_record_on_records(product.comments, cursor: cursor) },
            ],
            cursor: cursor,
          ),
          throttle_on: -> {
            self.class.events << :check
            self.class.throttle_sequence.shift || false
          },
          backoff: 30.seconds,
          check_before_fetch: true,
        )
      end

      def each_iteration(comment)
        self.class.events << :process
        self.class.processed_ids << comment.id
      end
    end

    # Responds to #each (and #size) but is not an Enumerator.
    class EachOnly
      def initialize(values)
        @values = values
      end

      def each(&block)
        @values.each(&block)
      end

      def size
        @values.size
      end
    end

    setup do
      IterationThrottleJob.iterations_performed = []

      ActiveRecordThrottleJob.builder_method = :active_record_on_batches
      ActiveRecordThrottleJob.check_before_fetch = true
      ActiveRecordThrottleJob.throttle_sequence = []
      ActiveRecordThrottleJob.events = []
      ActiveRecordThrottleJob.processed_ids = []
      ActiveRecordThrottleJob.on_complete_called = 0

      StackedThrottleJob.events = []

      NestedThrottleJob.throttle_sequence = []
      NestedThrottleJob.events = []
      NestedThrottleJob.processed_ids = []
    end

    teardown do
      IterationThrottleJob.on_complete_called = 0
      IterationThrottleJob.should_throttle_sequence = []
    end

    test "throttle enumerator proxies wrapped enumerator" do
      enum = enumerator_builder.array([1, 2, 3], cursor: nil)
      throttle_enum = enumerator_builder
        .throttle(
          enum,
          throttle_on: -> { false },
          backoff: 30.seconds,
        )

      assert_equal enum.size, throttle_enum.size
      assert_equal enum.map { |e| e }, throttle_enum.map { |e| e }
    end

    test "yields value and a cursor with splat" do
      enum = enumerator_builder.build_throttle_enumerator(
        enumerator_builder.active_record_on_records(Product.all, cursor: nil),
        throttle_on: -> { false },
        backoff: 30.seconds,
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
      assert_equal 1, enqueued.first.fetch("times_interrupted")

      assert_equal [1], IterationThrottleJob.iterations_performed
    end

    test "pushes job back to the queue with the configured throttle backoff" do
      IterationThrottleJob.should_throttle_sequence = [true]

      with_global_default_retry_backoff(15.seconds) do
        freeze_time do
          IterationThrottleJob.perform_now({})

          job = ActiveJob::Base.queue_adapter.enqueued_jobs.first
          assert_equal(30.seconds.from_now.to_f, job.fetch(:at))
        end
      end
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

    test "does not evaluate enumerator when throttled" do
      skip_until_version("2.0.0")
      CustomizableThrottleJob.perform_now({
        enumerator: Enumerator.new { raise StandardError, "should not evaluate when throttled" },
        throttle_on: -> { true },
      })
    end

    test "can only wrap another enumerator" do
      skip_until_version("2.0.0")
      error = assert_raises(ArgumentError) do
        CustomizableThrottleJob.perform_now({
          enumerator: [],
          throttle_on: -> { true },
        })
      end
      assert_equal("wrapped object must be Enumerator, not Array", error.message)
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

    test "check_before_fetch: false (the default) fetches the next value before checking the throttle" do
      ActiveRecordThrottleJob.check_before_fetch = false
      ActiveRecordThrottleJob.throttle_sequence = [true]

      run_tracking_fetches(ActiveRecordThrottleJob) { ActiveRecordThrottleJob.perform_now }

      assert_equal [:fetch, :check], ActiveRecordThrottleJob.events
      assert_empty ActiveRecordThrottleJob.processed_ids
      assert_equal 1, ActiveJob::Base.queue_adapter.enqueued_jobs.size
    end

    test "check_before_fetch: false (the default) calls throttle_on once per value" do
      ActiveRecordThrottleJob.check_before_fetch = false

      run_tracking_fetches(ActiveRecordThrottleJob) { ActiveRecordThrottleJob.perform_now }

      assert_equal 4, ActiveRecordThrottleJob.events.count(:process)
      assert_equal 4, ActiveRecordThrottleJob.events.count(:check)
      assert_equal Product.order(:id).ids, ActiveRecordThrottleJob.processed_ids
    end

    [:active_record_on_records, :active_record_on_batches, :active_record_on_batch_relations].each do |builder_method|
      test "check_before_fetch: true does not query when throttled before the first value (#{builder_method})" do
        ActiveRecordThrottleJob.builder_method = builder_method
        ActiveRecordThrottleJob.throttle_sequence = [true]

        run_tracking_fetches(ActiveRecordThrottleJob) { ActiveRecordThrottleJob.perform_now }

        assert_equal [:check], ActiveRecordThrottleJob.events
        assert_empty ActiveRecordThrottleJob.processed_ids
        enqueued = ActiveJob::Base.queue_adapter.enqueued_jobs
        assert_equal 1, enqueued.size
        assert_nil enqueued.first.fetch("cursor_position")
        assert_equal 0, ActiveRecordThrottleJob.on_complete_called
      end

      test "check_before_fetch: true resumes after a throttle without skipping or repeating values (#{builder_method})" do
        ActiveRecordThrottleJob.builder_method = builder_method
        # Before the first fetch, after the first value, then throttle after the second value.
        ActiveRecordThrottleJob.throttle_sequence = [false, false, true]

        run_tracking_fetches(ActiveRecordThrottleJob) { ActiveRecordThrottleJob.perform_now }

        assert_equal 2, ActiveRecordThrottleJob.events.count(:process)
        assert_equal :check, ActiveRecordThrottleJob.events.last
        assert_equal 1, ActiveJob::Base.queue_adapter.enqueued_jobs.size

        run_tracking_fetches(ActiveRecordThrottleJob) { work_one_job }

        assert_equal Product.order(:id).ids, ActiveRecordThrottleJob.processed_ids
        assert_empty ActiveJob::Base.queue_adapter.enqueued_jobs
        assert_equal 1, ActiveRecordThrottleJob.on_complete_called
      end
    end

    test "check_before_fetch: true checks before each fetch, so a throttled run never discards a fetched page" do
      # Four pages of 3, 3, 3 and 1 products. Throttle after the second page.
      ActiveRecordThrottleJob.throttle_sequence = [false, false, true]

      run_tracking_fetches(ActiveRecordThrottleJob) { ActiveRecordThrottleJob.perform_now }

      assert_equal [:check, :fetch, :process, :check, :fetch, :process, :check], ActiveRecordThrottleJob.events
      assert_equal Product.order(:id).limit(6).ids, ActiveRecordThrottleJob.processed_ids
    end

    test "check_before_fetch: true makes the same queries as the default on a healthy run, plus one throttle call" do
      run_tracking_fetches(ActiveRecordThrottleJob) { ActiveRecordThrottleJob.perform_now }
      with_option = ActiveRecordThrottleJob.events.dup

      ActiveRecordThrottleJob.check_before_fetch = false
      ActiveRecordThrottleJob.events = []
      ActiveRecordThrottleJob.processed_ids = []
      run_tracking_fetches(ActiveRecordThrottleJob) { ActiveRecordThrottleJob.perform_now }
      without_option = ActiveRecordThrottleJob.events

      assert_equal without_option.count(:fetch), with_option.count(:fetch)
      assert_equal 4, with_option.count(:process)
      assert_equal 5, with_option.count(:check)
      assert_equal 4, without_option.count(:check)
      assert_equal 2, ActiveRecordThrottleJob.on_complete_called
      assert_equal Product.order(:id).ids, ActiveRecordThrottleJob.processed_ids
    end

    test "check_before_fetch: true can throttle after the last value; the next run only makes an empty fetch" do
      # Throttle on the check after the fourth and last page.
      ActiveRecordThrottleJob.throttle_sequence = [false, false, false, false, true]

      run_tracking_fetches(ActiveRecordThrottleJob) { ActiveRecordThrottleJob.perform_now }

      assert_equal Product.order(:id).ids, ActiveRecordThrottleJob.processed_ids
      assert_equal 0, ActiveRecordThrottleJob.on_complete_called
      assert_equal 1, ActiveJob::Base.queue_adapter.enqueued_jobs.size

      ActiveRecordThrottleJob.events = []
      run_tracking_fetches(ActiveRecordThrottleJob) { work_one_job }

      assert_equal [:check, :fetch], ActiveRecordThrottleJob.events
      assert_equal Product.order(:id).ids, ActiveRecordThrottleJob.processed_ids
      assert_equal 1, ActiveRecordThrottleJob.on_complete_called
      assert_empty ActiveJob::Base.queue_adapter.enqueued_jobs
    end

    test "check_before_fetch: true on active_record_on_records still discards the rest of a loaded page" do
      ActiveRecordThrottleJob.builder_method = :active_record_on_records
      # Throttle after the first record of the first page of 3.
      ActiveRecordThrottleJob.throttle_sequence = [false, true]

      run_tracking_fetches(ActiveRecordThrottleJob) { ActiveRecordThrottleJob.perform_now }

      assert_equal [:check, :fetch, :process, :check], ActiveRecordThrottleJob.events

      ActiveRecordThrottleJob.events = []
      run_tracking_fetches(ActiveRecordThrottleJob) { work_one_job }

      # The resumed run fetches the page again, starting after the processed record.
      assert_equal [:check, :fetch, :process], ActiveRecordThrottleJob.events.first(3)
      assert_equal Product.order(:id).ids, ActiveRecordThrottleJob.processed_ids
    end

    test "stacked throttles check the inner throttle after the fetch by default" do
      StackedThrottleJob.check_before_fetch = false

      run_tracking_fetches(StackedThrottleJob) { StackedThrottleJob.perform_now }

      assert_equal(
        [
          :fetch, :inner, :outer, :process,
          :fetch, :inner, :outer, :process,
          :fetch,
        ],
        StackedThrottleJob.events,
      )
    end

    test "stacked throttles with check_before_fetch: true check outer then inner, both before the fetch" do
      StackedThrottleJob.check_before_fetch = true

      run_tracking_fetches(StackedThrottleJob) { StackedThrottleJob.perform_now }

      assert_equal(
        [
          :outer, :inner, :fetch, :process,
          :outer, :inner, :fetch, :process,
          :outer, :inner, :fetch,
        ],
        StackedThrottleJob.events,
      )
    end

    test "check_before_fetch: true wrapping a nested enumerator checks before fetching the next parent or child" do
      # Products with comments have 1, 2 and 3 comments. Throttle after the only comment of the first product.
      NestedThrottleJob.throttle_sequence = [false, true]

      run_tracking_fetches(NestedThrottleJob) { NestedThrottleJob.perform_now }

      # One fetch for the page of products and one for the first product's comments; nothing after the throttle.
      assert_equal [:check, :fetch, :fetch, :process, :check], NestedThrottleJob.events

      run_tracking_fetches(NestedThrottleJob) { work_one_job }

      assert_equal Comment.order(:product_id, :id).ids, NestedThrottleJob.processed_ids
      assert_empty ActiveJob::Base.queue_adapter.enqueued_jobs
    end

    test "check_before_fetch: true does not evaluate the enumerator when throttled" do
      enum = enumerator_builder.build_throttle_enumerator(
        Enumerator.new { raise StandardError, "should not evaluate when throttled" },
        throttle_on: -> { true },
        backoff: 30.seconds,
        check_before_fetch: true,
      )

      thrown = catch(:abort) do
        enum.each { flunk("should not yield when throttled") }
        :not_thrown
      end

      assert_equal [:retry, 30.seconds], thrown
    end

    test "check_before_fetch: true still wraps an object that only responds to #each" do
      checks = 0
      enum = enumerator_builder.build_throttle_enumerator(
        EachOnly.new([[:a, 0], [:b, 1], [:c, 2]]),
        throttle_on: -> {
          checks += 1
          false
        },
        backoff: 30.seconds,
        check_before_fetch: true,
      )

      assert_equal 3, enum.size
      assert_equal [[:a, 0], [:b, 1], [:c, 2]], enum.map { |value, cursor| [value, cursor] }
      assert_equal 4, checks
    end

    test "check_before_fetch: true keeps the wrapped enumerator's size" do
      enum = enumerator_builder.array([1, 2, 3], cursor: nil)
      throttle_enum = enumerator_builder.throttle(enum, throttle_on: -> { false }, backoff: 30.seconds, check_before_fetch: true)

      assert_equal enum.size, throttle_enum.size
      assert_equal enum.map { |e| e }, throttle_enum.map { |e| e }
    end

    test "check_before_fetch: true instruments the throttle event" do
      payloads = []
      callback = ->(_event, _started, _finished, _id, payload) { payloads << payload }
      ActiveRecordThrottleJob.throttle_sequence = [false, true]
      ActiveSupport::Notifications.subscribed(callback, "throttled.iteration") do
        ActiveRecordThrottleJob.perform_now
      end

      assert_equal [{ job_class: ActiveRecordThrottleJob.name }], payloads
    end

    class << self
      def untracked
        previous = Thread.current[:throttle_enumerator_test_untracked]
        Thread.current[:throttle_enumerator_test_untracked] = true
        yield
      ensure
        Thread.current[:throttle_enumerator_test_untracked] = previous
      end
    end

    private

    # Appends :fetch to job_class.events for every query against products or comments made outside each_iteration.
    def run_tracking_fetches(job_class, &block)
      callback = ->(*, payload) {
        next if payload[:name] == "SCHEMA"
        next if Thread.current[:throttle_enumerator_test_untracked]
        next unless payload[:sql].match?(/FROM `(products|comments)`/)

        job_class.events << :fetch
      }
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record", &block)
    end

    def work_one_job
      job = ActiveJob::Base.queue_adapter.enqueued_jobs.pop
      ActiveJob::Base.execute(job)
    end

    def enumerator_builder
      JobIteration::EnumeratorBuilder.new(nil)
    end
  end
end
