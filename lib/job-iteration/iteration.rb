# frozen_string_literal: true

require "active_support/all"

module JobIteration
  module Iteration
    extend ActiveSupport::Concern

    attr_accessor(
      :cursor_position,
      :times_interrupted,
    )

    # The time when the job starts running. If the job is interrupted and runs again, the value is updated.
    attr_accessor :start_time

    # The total time the job has been running, including multiple iterations.
    # The time isn't reset if the job is interrupted.
    attr_accessor :total_time

    included do |_base|
      define_callbacks :start
      define_callbacks :shutdown
      define_callbacks :complete

      class_attribute(
        :job_iteration_max_job_runtime,
        instance_accessor: false,
        instance_predicate: false,
      )

      class_attribute(
        :job_iteration_enforce_serializable_cursors,
        instance_accessor: false,
        instance_predicate: false,
      )
    end

    module ClassMethods
      def method_added(method_name)
        ban_perform_definition if method_name.to_sym == :perform
        super
      end

      def on_start(*filters, &blk)
        set_callback(:start, :after, *filters, &blk)
      end

      def on_shutdown(*filters, &blk)
        set_callback(:shutdown, :after, *filters, &blk)
      end

      def on_complete(*filters, &blk)
        set_callback(:complete, :after, *filters, &blk)
      end

      private

      def ban_perform_definition
        raise "Job that is using Iteration (#{self}) cannot redefine #perform"
      end
    end

    def initialize(*arguments)
      super
      @job_iteration_retry_backoff = JobIteration.default_retry_backoff
      @needs_reenqueue = false
      self.times_interrupted = 0
      self.total_time = 0.0
      assert_implements_methods!
    end
    ruby2_keywords(:initialize) if respond_to?(:ruby2_keywords, true)

    def serialize # @private
      iteration_job_data = {
        "cursor_position" => cursor_position, # Backwards compatibility
        "times_interrupted" => times_interrupted,
        "total_time" => total_time,
      }

      begin
        iteration_job_data["serialized_cursor_position"] = serialize_cursor(cursor_position)
      rescue ActiveJob::SerializationError
        raise if job_iteration_enforce_serializable_cursors?
        # No point in duplicating the deprecation warning from assert_valid_cursor!
      end

      super.merge(iteration_job_data)
    end

    def deserialize(job_data) # @private
      super
      self.cursor_position = cursor_position_from_job_data(job_data)
      self.times_interrupted = Integer(job_data["times_interrupted"] || 0)
      self.total_time = Float(job_data["total_time"] || 0.0)
    end

    def perform(*params) # @private
      interruptible_perform(*params)

      nil
    end

    def retry_job(*, **)
      super unless defined?(@retried) && @retried
      @retried = true
    end

    private

    def enumerator_builder
      JobIteration.enumerator_builder.new(self)
    end

    def interruptible_perform(*arguments)
      self.start_time = Time.now.utc

      enumerator = nil
      ActiveSupport::Notifications.instrument("build_enumerator.iteration", instrumentation_tags) do
        enumerator = build_enumerator(*arguments, cursor: cursor_position)
      end

      unless enumerator
        ActiveSupport::Notifications.instrument("nil_enumerator.iteration", instrumentation_tags)
        return
      end

      assert_enumerator!(enumerator)

      if executions == 1 && times_interrupted == 0
        run_callbacks(:start)
      else
        ActiveSupport::Notifications.instrument(
          "resumed.iteration",
          instrumentation_tags.merge(times_interrupted: times_interrupted, total_time: total_time),
        )
      end

      completed = catch(:abort) do
        iterate_with_enumerator(enumerator, arguments)
      end

      run_callbacks(:shutdown)
      completed = handle_completed(completed)

      if @needs_reenqueue
        reenqueue_iteration_job
      elsif completed
        run_callbacks(:complete)
        ActiveSupport::Notifications.instrument(
          "completed.iteration",
          instrumentation_tags.merge(times_interrupted: times_interrupted, total_time: total_time),
        )
      end
    end

    def iterate_with_enumerator(enumerator, arguments)
      arguments = arguments.dup.freeze
      found_record = false
      @needs_reenqueue = false

      enumerator.each do |object_from_enumerator, cursor_from_enumerator|
        assert_valid_cursor!(cursor_from_enumerator)

        tags = instrumentation_tags.merge(cursor_position: cursor_from_enumerator)
        ActiveSupport::Notifications.instrument("each_iteration.iteration", tags) do
          found_record = true
          each_iteration(object_from_enumerator, *arguments)
          self.cursor_position = cursor_from_enumerator
        end

        next unless job_should_exit?

        self.executions -= 1 if executions > 1
        @needs_reenqueue = true
        return false
      end

      ActiveSupport::Notifications.instrument(
        "not_found.iteration",
        instrumentation_tags.merge(times_interrupted: times_interrupted),
      ) unless found_record

      true
    ensure
      adjust_total_time
    end

    def reenqueue_iteration_job
      ActiveSupport::Notifications.instrument("interrupted.iteration", instrumentation_tags)

      self.times_interrupted += 1

      self.already_in_queue = true if respond_to?(:already_in_queue=)
      retry_job(wait: @job_iteration_retry_backoff)
    end

    def adjust_total_time
      self.total_time += (Time.now.utc.to_f - start_time.to_f).round(6)
    end

    def assert_enumerator!(enum)
      return if enum.is_a?(Enumerator)

      raise ArgumentError, <<~EOS
        #build_enumerator is expected to return Enumerator object, but returned #{enum.class}.
        Example:
           def build_enumerator(params, cursor:)
            enumerator_builder.active_record_on_records(
              Shop.find(params[:shop_id]).products,
              cursor: cursor
            )
          end
      EOS
    end

    def assert_valid_cursor!(cursor)
      serialize_cursor(cursor)
    rescue ActiveJob::SerializationError
      raise if job_iteration_enforce_serializable_cursors?

      Deprecation.warn(<<~DEPRECATION_MESSAGE, caller_locations(3))
        The Enumerator returned by #{self.class.name}#build_enumerator yielded a cursor which is unsafe to serialize.
        See https://github.com/Shopify/job-iteration/blob/main/guides/custom-enumerator.md#cursor-types
        This will raise starting in version #{Deprecation.deprecation_horizon} of #{Deprecation.gem_name}!"
      DEPRECATION_MESSAGE
    end

    def assert_implements_methods!
      unless respond_to?(:each_iteration, true)
        raise(
          ArgumentError,
          "Iteration job (#{self.class}) must implement #each_iteration method",
        )
      end

      if respond_to?(:build_enumerator, true)
        parameters = method_parameters(:build_enumerator)
        unless valid_cursor_parameter?(parameters)
          raise ArgumentError, "Iteration job (#{self.class}) #build_enumerator " \
            "expects the keyword argument `cursor`"
        end
      else
        raise ArgumentError, "Iteration job (#{self.class}) must implement #build_enumerator " \
          "to provide a collection to iterate"
      end
    end

    def method_parameters(method_name)
      method = method(method_name)

      if defined?(T::Private::Methods)
        signature = T::Private::Methods.signature_for_method(method)
        method = signature.method if signature
      end

      method.parameters
    end

    def instrumentation_tags
      { job_class: self.class.name, cursor_position: cursor_position }
    end

    def job_should_exit?
      max_job_runtime = job_iteration_max_job_runtime
      return true if max_job_runtime && start_time && (Time.now.utc - start_time) > max_job_runtime

      JobIteration.interruption_adapter.call || (defined?(super) && super)
    end

    def job_iteration_max_job_runtime
      global_max = JobIteration.max_job_runtime
      class_max = self.class.job_iteration_max_job_runtime

      return global_max unless class_max
      return class_max unless global_max

      [global_max, class_max].min
    end

    def job_iteration_enforce_serializable_cursors? # TODO: Add a test for the edge case of registering it afterwards
      per_class_setting = self.class.job_iteration_enforce_serializable_cursors
      return per_class_setting unless per_class_setting.nil?

      !!JobIteration.enforce_serializable_cursors
    end

    def handle_completed(completed)
      case completed
      when nil # someone aborted the job but wants to call the on_complete callback
        return true
      when true
        return true
      when false, :skip_complete_callbacks
        return false
      when Array # used by ThrottleEnumerator
        reason, backoff = completed
        raise "Unknown reason: #{reason}" unless reason == :retry

        @job_iteration_retry_backoff = backoff
        @needs_reenqueue = true
        return false
      end
      raise "Unexpected thrown value: #{completed.inspect}"
    end

    def cursor_position_from_job_data(job_data)
      if job_data.key?("serialized_cursor_position")
        deserialize_cursor(job_data.fetch("serialized_cursor_position"))
      else
        # Backwards compatibility for
        # - jobs interrupted before cursor serialization feature shipped, or
        # - jobs whose cursor could not be serialized
        job_data.fetch("cursor_position", nil)
      end
    end

    def serialize_cursor(cursor)
      ActiveJob::Arguments.serialize([cursor]).first
    end

    def deserialize_cursor(cursor)
      ActiveJob::Arguments.deserialize([cursor]).first
    end

    def valid_cursor_parameter?(parameters)
      # this condition is when people use the splat operator.
      # def build_enumerator(*)
      return true if parameters == [[:rest]] || parameters == [[:rest, :*]]

      parameters.each do |parameter_type, parameter_name|
        next unless parameter_name == :cursor
        return true if [:keyreq, :key].include?(parameter_type)
      end
      false
    end
  end
end
