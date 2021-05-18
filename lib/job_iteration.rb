# frozen_string_literal: true

require_relative "./job_iteration/version"
require_relative "./job_iteration/enumerator_builder"
require_relative "./job_iteration/iteration"
require_relative "./job_iteration/integrations"

module JobIteration
  extend self

  # Use this to _always_ interrupt the job after it's been running for more than N seconds.
  # @example
  #
  #   JobIteration.max_job_runtime = 5.minutes
  #
  # This setting will make it to always interrupt a job after it's been iterating for 5 minutes.
  # Defaults to nil which means that jobs will not be interrupted except on termination signal.
  attr_accessor :max_job_runtime

  # Set if you want to use your own enumerator builder instead of default EnumeratorBuilder.
  # @example
  #
  #   class MyOwnBuilder < JobIteration::EnumeratorBuilder
  #     # ...
  #   end
  #
  #   JobIteration.enumerator_builder = MyOwnBuilder
  attr_accessor :enumerator_builder
  self.enumerator_builder = JobIteration::EnumeratorBuilder

  # Used internally for hooking into job processing frameworks like Sidekiq and Resque.
  def self.load_interruption_integration(integration)
    JobIteration::Integrations.load(integration)
  end
end
