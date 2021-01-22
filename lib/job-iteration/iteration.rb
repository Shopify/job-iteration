# frozen_string_literal: true

require 'active_support/all'

module JobIteration
  module Iteration
    extend ActiveSupport::Concern

    included do |_base|
      attr_accessor(
        :cursor_position,
        :start_time,
        :times_interrupted,
        :total_time,
      )

      define_callbacks :start
      define_callbacks :shutdown
      define_callbacks :complete
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
      self.times_interrupted = 0
      self.total_time = 0.0
      assert_implements_methods!
    end
    ruby2_keywords(:initialize) if respond_to?(:ruby2_keywords, true)

    def serialize # @private
      super.merge(
        'cursor_position' => cursor_position,
        'times_interrupted' => times_interrupted,
        'total_time' => total_time,
      )
    end

    def deserialize(job_data) # @private
      super
      self.cursor_position = job_data['cursor_position']
      self.times_interrupted = job_data['times_interrupted'] || 0
      self.total_time = job_data['total_time'] || 0
    end

    def perform(*params) # @private
      interruptible_perform(*params)
    end

    def retry_job(*, **)
      super unless defined?(@retried) && @retried
      @retried = true
    end

    private

    def build_enumerator(*arguments, cursor:)
      build_deferred_enumerator(*arguments).call(cursor: cursor)
    end

    def deferred_enumerator_builder
      JobIteration.deferred_enumerator_builder.new(self)
    end

    def enumerator_builder
      JobIteration.enumerator_builder.new(self)
    end

    def interruptible_perform(*arguments)
      self.start_time = Time.now.utc

      enumerator = nil
      ActiveSupport::Notifications.instrument("build_enumerator.iteration", iteration_instrumentation_tags) do
        enumerator = build_enumerator(*arguments, cursor: cursor_position)
      end

      unless enumerator
        logger.info("[JobIteration::Iteration] `build_enumerator` returned nil. " \
          "Skipping the job.")
        return
      end

      assert_enumerator!(enumerator)

      if executions == 1 && times_interrupted == 0
        run_callbacks(:start)
      else
        ActiveSupport::Notifications.instrument("resumed.iteration", iteration_instrumentation_tags)
      end

      completed = catch(:abort) do
        iterate_with_enumerator(enumerator, arguments)
      end

      run_callbacks(:shutdown)

      if run_complete_callbacks?(completed)
        run_callbacks(:complete)
        output_interrupt_summary
      end
    end

    def iterate_with_enumerator(enumerator, arguments)
      arguments = arguments.dup.freeze
      found_record = false
      enumerator.each do |object_from_enumerator, index|
        record_unit_of_work do
          found_record = true
          each_iteration(object_from_enumerator, *arguments)
          self.cursor_position = index
        end

        next unless job_should_exit?
        self.executions -= 1 if executions > 1
        reenqueue_iteration_job
        return false
      end

      logger.info(
        "[JobIteration::Iteration] Enumerator found nothing to iterate! " \
        "times_interrupted=#{times_interrupted} cursor_position=#{cursor_position}"
      ) unless found_record

      true
    end

    def record_unit_of_work
      ActiveSupport::Notifications.instrument("each_iteration.iteration", iteration_instrumentation_tags) do
        yield
      end
    end

    def reenqueue_iteration_job
      ActiveSupport::Notifications.instrument("interrupted.iteration", iteration_instrumentation_tags)
      logger.info("[JobIteration::Iteration] Interrupting and re-enqueueing the job cursor_position=#{cursor_position}")

      adjust_total_time
      self.times_interrupted += 1

      self.already_in_queue = true if respond_to?(:already_in_queue=)
      retry_job
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

    def assert_implements_methods!
      unless respond_to?(:each_iteration, true)
        raise(
          ArgumentError,
          "Iteration job (#{self.class}) must implement #each_iteration method"
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

    def iteration_instrumentation_tags
      { job_class: self.class.name }
    end

    def output_interrupt_summary
      adjust_total_time

      message = "[JobIteration::Iteration] Completed iterating. times_interrupted=%d total_time=%.3f"
      logger.info(Kernel.format(message, times_interrupted, total_time))
    end

    def job_should_exit?
      if ::JobIteration.max_job_runtime && start_time && (Time.now.utc - start_time) > ::JobIteration.max_job_runtime
        return true
      end

      JobIteration.interruption_adapter.call || (defined?(super) && super)
    end

    def run_complete_callbacks?(completed)
      # nil means that someone aborted the job but want to call the on_complete callback
      if completed.nil?
        completed = :finished
      end

      case completed
      when :finished, true then true
      # skip_complete_callbacks is returning from ThrottleEnumeratorand we do not want the on_complete callback to
      # be executed
      when false, :skip_complete_callbacks then false
      end
    end

    def valid_cursor_parameter?(parameters)
      # this condition is when people use the splat operator.
      # def build_enumerator(*)
      return true if parameters == [[:rest]]

      parameters.each do |parameter_type, parameter_name|
        next unless parameter_name == :cursor
        return true if [:keyreq, :key].include?(parameter_type)
      end
      false
    end
  end
end
