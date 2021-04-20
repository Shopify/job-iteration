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
      return if Gem::Version.new(JobIteration::VERSION) < Gem::Version.new("2.0")
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

  def test_jobs_using_time_cursor_is_deprecated
    push(JobWithTimeCursor)
    assert_cursor_deprecation_warning { work_one_job }
  end

  def test_jobs_using_active_record_cursor_is_deprecated
    refute_nil(Product.first)
    push(JobWithActiveRecordCursor)
    assert_cursor_deprecation_warning { work_one_job }
  end

  def test_jobs_using_symbol_cursor_is_deprecated
    push(JobWithSymbolCursor)
    assert_cursor_deprecation_warning { work_one_job }
  end

  def test_jobs_using_string_subclass_cursor_is_deprecated
    push(JobWithStringSubclassCursor)
    assert_cursor_deprecation_warning { work_one_job }
  end

  def test_jobs_using_basic_object_cursor_is_deprecated
    push(JobWithBasicObjectCursor)
    assert_cursor_deprecation_warning { work_one_job }
  end

  def test_jobs_using_complex_but_serializable_cursor_is_not_deprecated
    push(JobWithComplexCursor)
    assert_no_cursor_deprecation_warning do
      work_one_job
    end
  end

  def test_jobs_using_on_complete_have_accurate_total_time
    freeze_time do
      JobThatCompletesAfter3Seconds.perform_now(->(job) { assert_equal(3, job.total_time) })
    end
  end

  private

  def assert_cursor_deprecation_warning(&block)
    job_class = ActiveJob::Base.queue_adapter.enqueued_jobs.first.fetch("job_class")
    expected_message = <<~MESSAGE.chomp
      DEPRECATION WARNING: The Enumerator returned by #{job_class}#build_enumerator yielded a cursor which is unsafe to serialize.
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
      &block
    )

    assert(warned, "expected deprecation warning")
  end

  def assert_no_cursor_deprecation_warning(&block)
    with_deprecation_behavior(
      -> (message, *) { flunk("Expected no deprecation warning: #{message}") },
      &block
    )
  end

  def with_deprecation_behavior(behavior)
    original_behaviour = JobIteration::Deprecation.behavior
    JobIteration::Deprecation.behavior = behavior
    yield
  ensure
    JobIteration::Deprecation.behavior = original_behaviour
  end

  def push(job, *args)
    job.perform_later(*args)
  end

  def work_one_job
    job = ActiveJob::Base.queue_adapter.enqueued_jobs.pop
    ActiveJob::Base.execute(job)
  end
end
