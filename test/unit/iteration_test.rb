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

  class InfiniteCursorLoggingJob < ActiveJob::Base
    include JobIteration::Iteration
    class << self
      def cursors
        @cursors ||= []
      end
    end

    def build_enumerator(cursor:)
      self.class.cursors << cursor
      ["VALUE", "CURSOR"].cycle
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

  UnserializableCursor = Class.new

  class SerializableCursor
    include GlobalID::Identification

    def id
      "singleton"
    end

    class << self
      def find(_id)
        new
      end
    end
  end

  def test_jobs_using_unserializable_cursor_will_raise
    skip_until_version("2.0.0")

    job_class = build_invalid_cursor_job(cursor: UnserializableCursor.new)

    assert_raises(ActiveJob::SerializationError) do
      job_class.perform_now
    end
  end

  def test_jobs_using_unserializable_cursor_is_deprecated
    job_class = build_invalid_cursor_job(cursor: UnserializableCursor.new)

    assert_cursor_deprecation_warning_on_perform(job_class)
  end

  def test_jobs_using_serializable_cursor_is_not_deprecated
    job_class = build_invalid_cursor_job(cursor: SerializableCursor.new)

    assert_no_cursor_deprecation_warning_on_perform(job_class)
  end

  def test_jobs_using_complex_but_serializable_cursor_is_not_deprecated
    job_class = build_invalid_cursor_job(cursor: [{
      "string" => "abc",
      "integer" => 123,
      "float" => 4.56,
      "booleans" => [true, false],
      "null" => nil,
    }])

    assert_no_cursor_deprecation_warning_on_perform(job_class)
  end

  def test_jobs_using_unserializable_cursor_will_raise_if_enforce_serializable_cursors_globally_enabled
    with_global_enforce_serializable_cursors(true) do
      job_class = build_invalid_cursor_job(cursor: UnserializableCursor.new)

      assert_raises(ActiveJob::SerializationError) do
        job_class.perform_now
      end
    end
  end

  def test_jobs_using_unserializable_cursor_will_raise_if_enforce_serializable_cursors_set_per_class
    with_global_enforce_serializable_cursors(false) do
      job_class = build_invalid_cursor_job(cursor: UnserializableCursor.new)
      job_class.job_iteration_enforce_serializable_cursors = true

      assert_raises(ActiveJob::SerializationError) do
        job_class.perform_now
      end
    end
  end

  def test_jobs_using_unserializable_cursor_will_raise_if_enforce_serializable_cursors_set_in_parent
    with_global_enforce_serializable_cursors(false) do
      parent = build_invalid_cursor_job(cursor: UnserializableCursor.new)
      parent.job_iteration_enforce_serializable_cursors = true
      child = Class.new(parent)

      assert_raises(ActiveJob::SerializationError) do
        child.perform_now
      end
    end
  end

  def test_jobs_using_unserializable_cursor_will_not_raise_if_enforce_serializable_cursors_unset_per_class
    with_global_enforce_serializable_cursors(true) do
      job_class = build_invalid_cursor_job(cursor: UnserializableCursor.new)
      job_class.job_iteration_enforce_serializable_cursors = false

      assert_cursor_deprecation_warning_on_perform(job_class)
    end
  end

  def test_jobs_using_unserializable_cursor_when_interrupted_should_only_store_the_cursor_and_no_serialized_cursor
    # We must ensure to store the unserializable cursor in the same way the legacy code did, for backwards compability
    job_class = build_invalid_cursor_job(cursor: UnserializableCursor.new)
    with_interruption do
      assert_cursor_deprecation_warning_on_perform(job_class)
    end

    job_data = ActiveJob::Base.queue_adapter.enqueued_jobs.last
    refute_nil(job_data, "interrupted job expected in queue")
    assert_instance_of(UnserializableCursor, job_data.fetch("cursor_position"))
    refute_includes(job_data, "serialized_cursor_position")
  end

  def test_jobs_using_serializable_cursor_when_interrupted_should_store_both_legacy_cursor_and_serialized_cursor
    # We must ensure to store the legacy cursor for backwards compatibility.
    job_class = build_invalid_cursor_job(cursor: SerializableCursor.new)
    with_interruption do
      assert_no_cursor_deprecation_warning_on_perform(job_class)
    end

    job_data = ActiveJob::Base.queue_adapter.enqueued_jobs.last
    refute_nil(job_data, "interrupted job expected in queue")
    assert_instance_of(SerializableCursor, job_data.fetch("cursor_position"))
    assert_equal(
      ActiveJob::Arguments.serialize([SerializableCursor.new]).first,
      job_data.fetch("serialized_cursor_position"),
    )
  end

  def test_job_interrupted_with_only_cursor_position_should_resume
    # Simulates loading a job serialized by an old version of job-iteration
    with_interruption do
      InfiniteCursorLoggingJob.perform_now

      work_one_job do |job_data|
        job_data["cursor_position"] = "raw cursor"
        job_data.delete("serialized_cursor_position")
      end

      assert_equal("raw cursor", InfiniteCursorLoggingJob.cursors.last)
    end
  ensure
    InfiniteCursorLoggingJob.cursors.clear
  end

  def test_job_interrupted_with_serialized_cursor_position_should_ignore_unserialized_cursor_position
    # Simulates loading a job serialized by the current version of job-iteration
    with_interruption do
      InfiniteCursorLoggingJob.perform_now

      work_one_job do |job_data|
        job_data["cursor_position"] = "should be ignored"
        job_data["serialized_cursor_position"] = ActiveJob::Arguments.serialize([SerializableCursor.new]).first
      end

      assert_instance_of(SerializableCursor, InfiniteCursorLoggingJob.cursors.last)
    end
  ensure
    InfiniteCursorLoggingJob.cursors.clear
  end

  def test_job_resuming_with_invalid_serialized_cursor_position_should_raise
    with_interruption do
      InfiniteCursorLoggingJob.perform_now
      assert_raises(ActiveJob::DeserializationError) do
        work_one_job do |job_data|
          job_data["cursor_position"] = "should be ignored"
          job_data["serialized_cursor_position"] = UnserializableCursor.new # cannot be deserialized
        end
      end
    end
  ensure
    InfiniteCursorLoggingJob.cursors.clear
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

  def test_global_max_job_runtime_with_updated_value
    freeze_time
    with_global_max_job_runtime(10.minutes) do
      klass = build_slow_job_class(iterations: 3, iteration_duration: 30.seconds)
      with_global_max_job_runtime(1.minute) do
        klass.perform_now
        assert_partially_completed_job(cursor_position: 2)
      end
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

  def test_per_class_max_job_runtime_with_global_set_lower
    freeze_time
    with_global_max_job_runtime(30.seconds) do
      parent = build_slow_job_class(iterations: 3, iteration_duration: 30.seconds)
      child = Class.new(parent) do
        self.job_iteration_max_job_runtime = 1.minute
      end

      parent.perform_now
      assert_partially_completed_job(cursor_position: 1)
      ActiveJob::Base.queue_adapter.enqueued_jobs = []

      child.perform_now
      assert_partially_completed_job(cursor_position: 1)
    end
  end

  def test_unset_per_class_max_job_runtime_and_global_set
    freeze_time
    with_global_max_job_runtime(1.minute) do
      parent = build_slow_job_class(iterations: 3, iteration_duration: 30.seconds)
      parent.job_iteration_max_job_runtime = 30.seconds
      child = Class.new(parent) do
        self.job_iteration_max_job_runtime = nil
      end

      parent.perform_now
      assert_partially_completed_job(cursor_position: 1)
      ActiveJob::Base.queue_adapter.enqueued_jobs = []

      child.perform_now
      assert_partially_completed_job(cursor_position: 2)
    end
  end

  def test_unset_per_class_max_job_runtime_and_unset_global_and_set_parent
    freeze_time
    with_global_max_job_runtime(nil) do
      parent = build_slow_job_class(iterations: 3, iteration_duration: 30.seconds)
      parent.job_iteration_max_job_runtime = 30.seconds
      child = Class.new(parent) do
        self.job_iteration_max_job_runtime = nil
      end

      parent.perform_now
      assert_partially_completed_job(cursor_position: 1)
      ActiveJob::Base.queue_adapter.enqueued_jobs = []

      child.perform_now
      assert_empty(ActiveJob::Base.queue_adapter.enqueued_jobs)
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

  # This helper allows us to create a class that reads config at test time, instead of when this file is loaded
  def build_invalid_cursor_job(cursor:)
    test_cursor = cursor # so we don't collide with the method param below
    Class.new(ActiveJob::Base) do
      include JobIteration::Iteration
      define_method(:build_enumerator) do |cursor:|
        current_cursor = cursor
        [["item", current_cursor || test_cursor]].to_enum
      end
      define_method(:each_iteration) do |*|
        return if Gem::Version.new(JobIteration::VERSION) < Gem::Version.new("2.0")

        raise "Cursor invalid. Starting in version 2.0, this should never run!"
      end
      singleton_class.define_method(:name) do
        "InvalidCursorJob (#{cursor.class})"
      end
    end
  end

  def assert_cursor_deprecation_warning_on_perform(job_class)
    expected_message = <<~MESSAGE.chomp
      DEPRECATION WARNING: The Enumerator returned by #{job_class.name}#build_enumerator yielded a cursor which is unsafe to serialize.
      See https://github.com/Shopify/job-iteration/blob/main/guides/custom-enumerator.md#cursor-types
      This will raise starting in version #{JobIteration::Deprecation.deprecation_horizon} of #{JobIteration::Deprecation.gem_name}!
    MESSAGE

    warned = false
    with_deprecation_behavior(
      lambda do |message, *|
        flunk("expected only one deprecation warning") if warned
        warned = true
        assert(
          message.start_with?(expected_message),
          "expected deprecation warning \n#{message.inspect}\n to start_with? \n#{expected_message.inspect}",
        )
      end,
    ) { job_class.perform_now }

    assert(warned, "expected deprecation warning")
  end

  def assert_no_cursor_deprecation_warning_on_perform(job_class)
    with_deprecation_behavior(
      ->(message, *) { flunk("Expected no deprecation warning: #{message}") },
    ) { job_class.perform_now }
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
    job_data = ActiveJob::Base.queue_adapter.enqueued_jobs.pop
    yield job_data if block_given?
    ActiveJob::Base.execute(job_data)
  end

  def with_deprecation_behavior(behavior)
    original_behaviour = JobIteration::Deprecation.behavior
    JobIteration::Deprecation.behavior = behavior
    yield
  ensure
    JobIteration::Deprecation.behavior = original_behaviour
  end

  def with_global_enforce_serializable_cursors(temp)
    original = JobIteration.enforce_serializable_cursors
    JobIteration.enforce_serializable_cursors = temp
    yield
  ensure
    JobIteration.enforce_serializable_cursors = original
  end

  def with_interruption(&block)
    with_interruption_adapter(-> { true }, &block)
  end

  def with_interruption_adapter(temp)
    original = JobIteration.interruption_adapter
    JobIteration.interruption_adapter = temp
    yield
  ensure
    JobIteration.interruption_adapter = original
  end

  def with_global_max_job_runtime(new)
    original = JobIteration.max_job_runtime
    JobIteration.max_job_runtime = new
    yield
  ensure
    JobIteration.max_job_runtime = original
  end
end
