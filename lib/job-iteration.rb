# frozen_string_literal: true

require "job-iteration/version"
require "job-iteration/enumerator_builder"
require "job-iteration/iteration"

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
      require "job-iteration/integrations/#{integration}"
    rescue LoadError
    end
  end
end

JobIteration.load_integrations
