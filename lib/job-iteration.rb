# frozen_string_literal: true

require_relative "./job-iteration/version"
require_relative "./job-iteration/enumerator_builder"
require_relative "./job-iteration/iteration"

module JobIteration
  INTEGRATIONS = [:resque, :sidekiq]

  extend self

  attr_accessor :max_job_runtime, :interruption_adapter

  module AlwaysRunningInterruptionAdapter
    extend self

    def shutdown?
      false
    end
  end
  self.interruption_adapter = AlwaysRunningInterruptionAdapter

  def load_integrations
    INTEGRATIONS.each do |integration|
      begin
        require "job-iteration/integrations/#{integration}"
      rescue LoadError
      end
    end
  end
end

JobIteration.load_integrations unless ENV['ITERATION_DISABLE_AUTOCONFIGURE']
