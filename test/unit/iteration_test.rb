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

    job_class = build_invalid_cursor_job(cursor: Time.now)

    assert_raises_cursor_error do
      job_class.perform_now
    end
  end

  def test_jobs_using_time_cursor_is_deprecated
    job_class = build_invalid_cursor_job(cursor: Time.now)

    assert_cursor_deprecation_warning_on_perform(job_class)
  end

  def test_jobs_using_active_record_cursor_will_raise
    skip_until_version("2.0.0")

    refute_nil(Product.first)

    job_class = build_invalid_cursor_job(cursor: Product.first)

    assert_raises_cursor_error do
      job_class.perform_now
    end
  end

  def test_jobs_using_active_record_cursor_is_deprecated
    refute_nil(Product.first)

    job_class = build_invalid_cursor_job(cursor: Product.first)

    assert_cursor_deprecation_warning_on_perform(job_class)
  end

  def test_jobs_using_symbol_cursor_will_raise
    skip_until_version("2.0.0")

    job_class = build_invalid_cursor_job(cursor: :symbol)

    assert_raises_cursor_error do
      job_class.perform_now
    end
  end

  def test_jobs_using_symbol_cursor_is_deprecated
    job_class = build_invalid_cursor_job(cursor: :symbol)

    assert_cursor_deprecation_warning_on_perform(job_class)
  end

  def test_jobs_using_string_subclass_cursor_will_raise
    skip_until_version("2.0.0")

    string_subclass = Class.new(String)
    string_subclass.define_singleton_method(:name) { "StringSubclass" }

    job_class = build_invalid_cursor_job(cursor: string_subclass.new)

    assert_raises_cursor_error do
      job_class.perform_now
    end
  end

  def test_jobs_using_string_subclass_cursor_is_deprecated
    string_subclass = Class.new(String)
    string_subclass.define_singleton_method(:name) { "StringSubclass" }

    job_class = build_invalid_cursor_job(cursor: string_subclass.new)

    assert_cursor_deprecation_warning_on_perform(job_class)
  end

  def test_jobs_using_basic_object_cursor_will_raise
    skip_until_version("2.0.0")

    job_class = build_invalid_cursor_job(cursor: BasicObject.new)

    assert_raises_cursor_error do
      job_class.perform_now
    end
  end

  def test_jobs_using_basic_object_cursor_is_deprecated
    job_class = build_invalid_cursor_job(cursor: BasicObject.new)

    assert_cursor_deprecation_warning_on_perform(job_class)
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
      job_class = build_invalid_cursor_job(cursor: :unserializable)

      assert_raises_cursor_error do
        job_class.perform_now
      end
    end
  end

  def test_jobs_using_unserializable_cursor_will_raise_if_enforce_serializable_cursors_set_per_class
    with_global_enforce_serializable_cursors(false) do
      job_class = build_invalid_cursor_job(cursor: :unserializable)
      job_class.job_iteration_enforce_serializable_cursors = true

      assert_raises_cursor_error do
        job_class.perform_now
      end
    end
  end

  def test_jobs_using_unserializable_cursor_will_raise_if_enforce_serializable_cursors_set_in_parent
    with_global_enforce_serializable_cursors(false) do
      parent = build_invalid_cursor_job(cursor: :unserializable)
      parent.job_iteration_enforce_serializable_cursors = true
      child = Class.new(parent)

      assert_raises_cursor_error do
        child.perform_now
      end
    end
  end

  def test_jobs_using_unserializable_cursor_will_not_raise_if_enforce_serializable_cursors_unset_per_class
    with_global_enforce_serializable_cursors(true) do
      job_class = build_invalid_cursor_job(cursor: :unserializable)
      job_class.job_iteration_enforce_serializable_cursors = false

      assert_nothing_raised do
        job_class.perform_now
      end
    end
  end

  def test_jobs_using_on_complete_have_accurate_total_time
    freeze_time do
      JobThatCompletesAfter3Seconds.perform_now(->(job) { assert_equal(3, job.total_time) })
    end
  end

  private

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
        "JobWith#{cursor.class}Cursor"
      rescue NoMethodError
        "JobWithBasicObjectCursor"
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

  def assert_cursor_deprecation_warning_on_perform(job_class)
    expected_message = <<~MESSAGE.chomp
      DEPRECATION WARNING: The Enumerator returned by #{job_class.name}#build_enumerator yielded a cursor which is unsafe to serialize.
      Cursors must be composed of objects capable of built-in (de)serialization: Strings, Integers, Floats, Arrays, Hashes, true, false, or nil.
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

  def push(job, *args)
    job.perform_later(*args)
  end

  def work_one_job
    job = ActiveJob::Base.queue_adapter.enqueued_jobs.pop
    ActiveJob::Base.execute(job)
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
  ensure
    JobIteration.enforce_serializable_cursors = original
  end
end
