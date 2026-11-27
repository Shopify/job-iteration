# typed: true
# frozen_string_literal: true

module JobIteration
  # ThrottleEnumerator allows you to throttle iterations
  # based on external signal (e.g. database health).
  # @example
  #   def build_enumerator(_params, cursor:)
  #     enumerator_builder.build_throttle_enumerator(
  #       enumerator_builder.active_record_on_batches(
  #         Account.inactive,
  #         cursor: cursor
  #       ),
  #       throttle_on: -> { DatabaseStatus.unhealthy? },
  #       backoff: 30.seconds
  #     )
  #   end
  # The enumerator from above will mimic +active_record_on_batches+,
  # except when +DatabaseStatus.unhealthy?+ starts to return true.
  # In that case, it will re-enqueue the job with a specified backoff.
  #
  # By default, +throttle_on+ is called after the wrapped enumerator has produced the next value and before that value
  # is processed, so a throttled job has already fetched (and then discards) the next value. Pass
  # +check_before_fetch: true+ to call +throttle_on+ once before iteration starts and then after each value has been
  # processed, before the wrapped enumerator is asked for the next one. See the throttling guide for the trade-offs.
  class ThrottleEnumerator
    def initialize(enum, job, throttle_on:, backoff:, check_before_fetch: false)
      @enum = enum
      @job = job
      @throttle_on = throttle_on
      @backoff = backoff
      @check_before_fetch = check_before_fetch
    end

    def to_enum
      if @check_before_fetch
        Enumerator.new(-> { @enum.size }) do |yielder|
          throttle_if_needed

          @enum.each do |*val|
            yielder.yield(*val)

            throttle_if_needed
          end
        end
      else
        Enumerator.new(-> { @enum.size }) do |yielder|
          @enum.each do |*val|
            throttle_if_needed

            yielder.yield(*val)
          end
        end
      end
    end

    def should_throttle?
      @throttle_on.call
    end

    private

    def throttle_if_needed
      return unless should_throttle?

      ActiveSupport::Notifications.instrument("throttled.iteration", job_class: @job.class.name)
      throw(:abort, [:retry, @backoff])
    end
  end
end
