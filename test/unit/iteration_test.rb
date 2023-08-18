# frozen_string_literal: true

require "test_helper"
require "sorbet-runtime"

class JobIterationTest < IterationUnitTest
  class JobWithNoMethods < ActiveJob::Base
    include JobIteration::Iteration
  end

  class JobWithRightMethods < ActiveJob::Base
    include JobIteration::Iteration
    def build_enumerator(_params, cursor:)
      enumerator_builder.build_times_enumerator(2, cursor: cursor)
    end

    def each_iteration(*)
    end
  end

  class JobWithRightMethodsButWithSorbetSignatures < ActiveJob::Base
    extend T::Sig
    include JobIteration::Iteration

    sig { params(_params: T.untyped, cursor: T.untyped).returns(T::Enumerator[T.untyped]) }
    def build_enumerator(_params, cursor:)
      enumerator_builder.build_times_enumerator(2, cursor: cursor)
    end

    sig { params(product: T.untyped, params: T.untyped).void }
    def each_iteration(product, params)
    end
  end

  class JobWithRightMethodsButMissingCursorKeywordArgument < ActiveJob::Base
    include JobIteration::Iteration
    def build_enumerator(params, cursor)
      enumerator_builder.active_record_on_records(
        Product.where(id: params[:id]),
        cursor: cursor,
      )
    end

    def each_iteration(product, params)
    end
  end

  class JobWithRightMethodsUsingSplatInTheArguments < ActiveJob::Base
    include JobIteration::Iteration
    def build_enumerator(*)
    end

    def each_iteration(*)
    end
  end

  class JobWithRightMethodsUsingDefaultKeywordArgument < ActiveJob::Base
    include JobIteration::Iteration
    def build_enumerator(params, cursor: nil)
    end

    def each_iteration(*)
    end
  end

  class InvalidCursorJob < ActiveJob::Base
    include JobIteration::Iteration
    def each_iteration(*)
      raise "Cursor invalid. This should never run!"
    end
  end

  class JobWithTimeCursor < InvalidCursorJob
    def build_enumerator(cursor:)
      [["item", cursor || Time.now]].to_enum
    end
  end

  class JobWithSymbolCursor < InvalidCursorJob
    def build_enumerator(cursor:)
      [["item", cursor || :symbol]].to_enum
    end
  end

  class JobWithActiveRecordCursor < InvalidCursorJob
    def build_enumerator(cursor:)
      [["item", cursor || Product.first]].to_enum
    end
  end

  class JobWithStringSubclassCursor < InvalidCursorJob
    StringSubClass = Class.new(String)

    def build_enumerator(cursor:)
      [["item", cursor || StringSubClass.new]].to_enum
    end
  end

  class JobWithBasicObjectCursor < InvalidCursorJob
    def build_enumerator(cursor:)
      [["item", cursor || BasicObject.new]].to_enum
    end
  end

  class JobWithComplexCursor < ActiveJob::Base
    include JobIteration::Iteration
    def build_enumerator(cursor:)
      [[
        "item",
        cursor || [{
          "string" => "abc",
          "integer" => 123,
          "float" => 4.56,
          "booleans" => [true, false],
          "null" => nil,
        }],
      ]].to_enum
    end

    def each_iteration(*)
    end
  end

  class JobThatCompletesAfter3Seconds < ActiveJob::Base
    include JobIteration::Iteration
    include ActiveSupport::Testing::TimeHelpers
    def build_enumerator(assertions, cursor:)
      @assertions = assertions
      enumerator_builder.build_times_enumerator(3, cursor: cursor) # iterate 3 times
    end

    def each_iteration(*)
      travel(1.second) # each iteration takes 1 second
    end

    on_complete do
      @assertions.call(self)
    end
  end

  class FailingJob < ActiveJob::Base
    include JobIteration::Iteration
    include ActiveSupport::Testing::TimeHelpers

    def build_enumerator(cursor:)
      enumerator_builder.build_times_enumerator(1, cursor: cursor)
    end

    def each_iteration(*)
      travel(10.seconds)

      raise StandardError, "failing job"
    end
  end

  class SuccessfulJobWithInterruption < ActiveJob::Base
    include JobIteration::Iteration
    include ActiveSupport::Testing::TimeHelpers
    cattr_accessor :total_time_on_complete, instance_accessor: false
    self.total_time_on_complete = 0

    on_complete do
      self.class.total_time_on_complete = total_time
    end

    def build_enumerator(cursor:)
      enumerator_builder.build_times_enumerator(2, cursor: cursor)
    end

    def each_iteration(*)
      travel(10.seconds)
    end

    private

    def job_should_exit?
      cursor_position == 0 # interrupt on first run and never again.
    end
  end

  class JobWithNestedEnumerator < ActiveJob::Base
    include JobIteration::Iteration
    def build_enumerator(_params, cursor:)
      enumerator_builder.nested(
        [
          ->(cursor) {
            enumerator_builder.build_times_enumerator(3, cursor: cursor)
          },
          ->(_integer, cursor) {
            enumerator_builder.build_times_enumerator(4, cursor: cursor)
          },
        ],
        cursor: cursor,
      )
    end

    def each_iteration(*)
    end
  end

  def test_jobs_that_define_build_enumerator_and_each_iteration_will_not_raise
    push(JobWithRightMethods, "walrus" => "best")
    work_one_job
  end

  def test_jobs_that_define_build_enumerator_and_each_iteration_with_sigs_will_not_raise
    push(JobWithRightMethodsButWithSorbetSignatures, "walrus" => "best")
    work_one_job
  end

  def test_jobs_that_pass_splat_argument_to_build_enumerator_will_not_raise
    push(JobWithRightMethodsUsingSplatInTheArguments, {})
    work_one_job
  end

  def test_jobs_that_pass_default_keyword_argument_to_build_enumerator_will_not_raise
    push(JobWithRightMethodsUsingDefaultKeywordArgument, {})
    work_one_job
  end

  def test_jobs_that_do_not_define_build_enumerator_or_each_iteration_raises
    assert_raises(ArgumentError) do
      push(JobWithNoMethods)
    end
  end

  def test_jobs_that_defines_methods_but_do_not_declare_cursor_as_keyword_argument_raises
    assert_raises(ArgumentError) do
      push(JobWithRightMethodsButMissingCursorKeywordArgument, id: 1)
    end
  end

  def test_that_it_has_a_version_number
    refute_nil(::JobIteration::VERSION)
  end

  def test_that_the_registered_method_added_hook_calls_super
    methods_added = []

    hook_module = Module.new do
      define_method(:method_added) do |name|
        methods_added << name
      end
    end

    Class.new(ActiveJob::Base) do
      # The order below is important.
      # We want the Hook Module to add the `method_added` first
      # and then `Iteration` to override it. That means that if
      # the `method_added` in `Iteration` does not call `super`
      # `foo` will **not** be in the `methods_added` list.
      extend hook_module
      include JobIteration::Iteration

      def foo
      end
    end

    assert_includes(methods_added, :foo)
  end

  def test_jobs_using_time_cursor_will_raise
    skip_until_version("2.0.0")
    push(JobWithTimeCursor)
    assert_raises_cursor_error { work_one_job }
  end

  def test_jobs_using_active_record_cursor_will_raise
    skip_until_version("2.0.0")
    refute_nil(Product.first)
    push(JobWithActiveRecordCursor)
    assert_raises_cursor_error { work_one_job }
  end

  def test_jobs_using_symbol_cursor_will_raise
    skip_until_version("2.0.0")
    push(JobWithSymbolCursor)
    assert_raises_cursor_error { work_one_job }
  end

  def test_jobs_using_string_subclass_cursor_will_raise
    skip_until_version("2.0.0")
    push(JobWithStringSubclassCursor)
    assert_raises_cursor_error { work_one_job }
  end

  def test_jobs_using_basic_object_cursor_will_raise
    skip_until_version("2.0.0")
    push(JobWithBasicObjectCursor)
    assert_raises_cursor_error { work_one_job }
  end

  def test_jobs_using_complex_but_serializable_cursor_will_not_raise
    skip_until_version("2.0.0")
    push(JobWithComplexCursor)
    work_one_job
  end

  def test_jobs_using_on_complete_have_accurate_total_time
    freeze_time do
      JobThatCompletesAfter3Seconds.perform_now(->(job) { assert_equal(3, job.total_time) })
    end
  end

  def test_global_max_job_runtime
    freeze_time
    with_global_max_job_runtime(1.minute) do
      klass = build_slow_job_class(iterations: 3, iteration_duration: 30.seconds)
      klass.perform_now
      assert_partially_completed_job(cursor_position: 2)
    end
  end

  def test_per_class_max_job_runtime_with_default_global
    freeze_time
    parent = build_slow_job_class(iterations: 3, iteration_duration: 30.seconds)
    child = Class.new(parent) do
      self.job_iteration_max_job_runtime = 1.minute
    end

    parent.perform_now
    assert_empty(ActiveJob::Base.queue_adapter.enqueued_jobs)

    child.perform_now
    assert_partially_completed_job(cursor_position: 2)
  end

  def test_per_class_max_job_runtime_with_global_set_to_nil
    freeze_time
    with_global_max_job_runtime(nil) do
      parent = build_slow_job_class(iterations: 3, iteration_duration: 30.seconds)
      child = Class.new(parent) do
        self.job_iteration_max_job_runtime = 1.minute
      end

      parent.perform_now
      assert_empty(ActiveJob::Base.queue_adapter.enqueued_jobs)

      child.perform_now
      assert_partially_completed_job(cursor_position: 2)
    end
  end

  def test_per_class_max_job_runtime_with_global_set
    freeze_time
    with_global_max_job_runtime(1.minute) do
      parent = build_slow_job_class(iterations: 3, iteration_duration: 30.seconds)
      child = Class.new(parent) do
        self.job_iteration_max_job_runtime = 30.seconds
      end

      parent.perform_now
      assert_partially_completed_job(cursor_position: 2)
      ActiveJob::Base.queue_adapter.enqueued_jobs = []

      child.perform_now
      assert_partially_completed_job(cursor_position: 1)
    end
  end

  def test_max_job_runtime_cannot_unset_global
    with_global_max_job_runtime(30.seconds) do
      klass = Class.new(ActiveJob::Base) do
        include JobIteration::Iteration
      end

      error = assert_raises(ArgumentError) do
        klass.job_iteration_max_job_runtime = nil
      end

      assert_equal(
        "job_iteration_max_job_runtime may only decrease; " \
          "#{klass} tried to increase it from 30 seconds to nil (no limit)",
        error.message,
      )
    end
  end

  def test_max_job_runtime_cannot_be_higher_than_global
    with_global_max_job_runtime(30.seconds) do
      klass = Class.new(ActiveJob::Base) do
        include JobIteration::Iteration
      end

      error = assert_raises(ArgumentError) do
        klass.job_iteration_max_job_runtime = 1.minute
      end

      assert_equal(
        "job_iteration_max_job_runtime may only decrease; #{klass} tried to increase it from 30 seconds to 1 minute",
        error.message,
      )
    end
  end

  def test_max_job_runtime_cannot_be_higher_than_parent
    with_global_max_job_runtime(1.minute) do
      parent = Class.new(ActiveJob::Base) do
        include JobIteration::Iteration
        self.job_iteration_max_job_runtime = 30.seconds
      end
      child = Class.new(parent)

      error = assert_raises(ArgumentError) do
        child.job_iteration_max_job_runtime = 45.seconds
      end

      assert_equal(
        "job_iteration_max_job_runtime may only decrease; #{child} tried to increase it from 30 seconds to 45 seconds",
        error.message,
      )
    end
  end

  def test_total_time_is_updated_for_successful_jobs_with_interruptions
    freeze_time do
      push(SuccessfulJobWithInterruption)

      work_one_job
      job = ActiveJob::Base.deserialize(ActiveJob::Base.queue_adapter.enqueued_jobs.last)
      assert_equal(10, job.total_time)

      work_one_job
      assert_equal(20, SuccessfulJobWithInterruption.total_time_on_complete)
    end
  end

  def test_total_time_is_updated_for_failed_jobs
    freeze_time do
      job = FailingJob.new
      assert_raises(StandardError) { job.perform_now }

      assert_equal(10, job.total_time)
    end
  end

  def test_each_iteration_instrumentation
    events = []
    callback = lambda { |_, _, _, _, tags| events << tags }
    ActiveSupport::Notifications.subscribed(callback, "each_iteration.iteration") do
      JobWithRightMethods.perform_now({})
    end

    expected = [
      { job_class: "JobIterationTest::JobWithRightMethods", cursor_position: 0 },
      { job_class: "JobIterationTest::JobWithRightMethods", cursor_position: 1 },
    ]
    assert_equal(expected, events)
  end

  def test_exception_in_each_iteration_instrumentation
    events = []
    callback = lambda { |_, _, _, _, tags| events << tags.except(:exception, :exception_object) }
    ActiveSupport::Notifications.subscribed(callback, "each_iteration.iteration") do
      assert_raises(StandardError) { FailingJob.perform_now }
    end

    expected = [
      { job_class: "JobIterationTest::FailingJob", cursor_position: 0 },
    ]
    assert_equal(expected, events)
  end

  def test_nested_each_iteration_instrumentation
    events = []
    callback = lambda { |_, _, _, _, tags| events << tags }
    ActiveSupport::Notifications.subscribed(callback, "each_iteration.iteration") do
      JobWithNestedEnumerator.perform_now({})
    end

    expected = [
      { job_class: "JobIterationTest::JobWithNestedEnumerator", cursor_position: [nil, 0] },
      { job_class: "JobIterationTest::JobWithNestedEnumerator", cursor_position: [nil, 1] },
      { job_class: "JobIterationTest::JobWithNestedEnumerator", cursor_position: [nil, 2] },
      { job_class: "JobIterationTest::JobWithNestedEnumerator", cursor_position: [nil, 3] },
      { job_class: "JobIterationTest::JobWithNestedEnumerator", cursor_position: [0, 0] },
      { job_class: "JobIterationTest::JobWithNestedEnumerator", cursor_position: [0, 1] },
      { job_class: "JobIterationTest::JobWithNestedEnumerator", cursor_position: [0, 2] },
      { job_class: "JobIterationTest::JobWithNestedEnumerator", cursor_position: [0, 3] },
      { job_class: "JobIterationTest::JobWithNestedEnumerator", cursor_position: [1, 0] },
      { job_class: "JobIterationTest::JobWithNestedEnumerator", cursor_position: [1, 1] },
      { job_class: "JobIterationTest::JobWithNestedEnumerator", cursor_position: [1, 2] },
      { job_class: "JobIterationTest::JobWithNestedEnumerator", cursor_position: [1, 3] },
    ]
    assert_equal(expected, events)
  end

  def test_perform_returns_nil
    # i.e. perform is "void", and nobody should depend on the return value
    assert_nil(JobWithRightMethods.perform_now({}))
  end

  private

  # Allows building job classes that read max_job_runtime during the test,
  # instead of when this file is read
  def build_slow_job_class(iterations: 3, iteration_duration: 30.seconds)
    Class.new(ActiveJob::Base) do
      include JobIteration::Iteration
      include ActiveSupport::Testing::TimeHelpers

      define_method(:build_enumerator) do |cursor:|
        enumerator_builder.build_times_enumerator(iterations, cursor: cursor)
      end

      define_method(:each_iteration) do |*|
        travel(iteration_duration)
      end
    end
  end

  def assert_raises_cursor_error(&block)
    error = assert_raises(JobIteration::Iteration::CursorError, &block)
    inspected_cursor =
      begin
        error.cursor.inspect
      rescue NoMethodError
        Object.instance_method(:inspect).bind(error.cursor).call
      end

    assert_equal(
      "Cursor must be composed of objects capable of built-in (de)serialization: " \
        "Strings, Integers, Floats, Arrays, Hashes, true, false, or nil. " \
        "(#{inspected_cursor})",
      error.message,
    )
  end

  def assert_partially_completed_job(cursor_position:)
    message = "Expected to find partially completed job enqueued with cursor_position: #{cursor_position}"
    enqueued_job = ActiveJob::Base.queue_adapter.enqueued_jobs.first
    refute_nil(enqueued_job, message)
    assert_equal(cursor_position, enqueued_job.fetch("cursor_position"))
  end

  def push(job, *args)
    job.perform_later(*args)
  end

  def work_one_job
    job = ActiveJob::Base.queue_adapter.enqueued_jobs.pop
    ActiveJob::Base.execute(job)
  end

  def with_global_max_job_runtime(new)
    original = JobIteration.max_job_runtime
    JobIteration.max_job_runtime = new
    yield
  ensure
    JobIteration.max_job_runtime = original
  end
end
