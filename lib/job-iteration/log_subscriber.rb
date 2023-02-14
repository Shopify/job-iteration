# frozen_string_literal: true

module JobIteration
  class LogSubscriber < ActiveSupport::LogSubscriber
    def logger
      JobIteration.logger
    end

    def nil_enumerator(event)
      info do
        "[JobIteration::Iteration] `build_enumerator` returned nil. Skipping the job."
      end
    end

    def not_found(event)
      info do
        "[JobIteration::Iteration] Enumerator found nothing to iterate! " \
          "times_interrupted=#{event.payload[:times_interrupted]} cursor_position=#{event.payload[:cursor_position]}"
      end
    end

    def interrupted(event)
      info do
        "[JobIteration::Iteration] Interrupting and re-enqueueing the job " \
          "cursor_position=#{event.payload[:cursor_position]}"
      end
    end

    def completed(event)
      info do
        message = "[JobIteration::Iteration] Completed iterating. times_interrupted=%d total_time=%.3f"
        Kernel.format(message, event.payload[:times_interrupted], event.payload[:total_time])
      end
    end
  end
end

JobIteration::LogSubscriber.attach_to(:iteration)
