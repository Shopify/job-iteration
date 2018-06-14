# frozen_string_literal: true

require "job-iteration/version"
require "job-iteration/enumerator_builder"
require "job-iteration/iteration"

module JobIteration
  INTEGRATIONS = [:resque, :sidekiq]

  def self.load_integrations
    INTEGRATIONS.each do |integration|
      begin
        require "job-iteration/integrations/#{integration}"
      rescue LoadError
      end
    end
  end
end

JobIteration.load_integrations
