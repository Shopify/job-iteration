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
  class ThrottleEnumerator
    def initialize(enum, job, throttle_on:, backoff:)
      @enum = enum
      @job = job
      @throttle_on = throttle_on
      @backoff = backoff
    end

    def to_enum
      Enumerator.new(-> { @enum.size }) do |yielder|
        @enum.each do |*val|
          if should_throttle?
            ActiveSupport::Notifications.instrument("throttled.iteration", job_class: @job.class.name)
            @job.run_callbacks(:reenqueue) do
              @job.reenqueue_iteration_job(wait: @backoff)
            end
            throw(:abort, :skip_complete_callbacks)
          end

          yielder.yield(*val)
        end
      end
    end

    def should_throttle?
      @throttle_on.call
    end
  end
end
