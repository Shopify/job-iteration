# frozen_string_literal: true

require "active_job"
require_relative "./job-iteration/version"
require_relative "./job-iteration/integrations"
require_relative "./job-iteration/enumerator_builder"
require_relative "./job-iteration/iteration"
require_relative "./job-iteration/log_subscriber"

module JobIteration
  extend self

  attr_accessor :logger

  self.logger = ActiveJob::Base.logger

  # Use this to _always_ interrupt the job after it's been running for more than N seconds.
  # @example
  #
  #   JobIteration.max_job_runtime = 5.minutes
  #
  # This setting will make it to always interrupt a job after it's been iterating for 5 minutes.
  # Defaults to nil which means that jobs will not be interrupted except on termination signal.
  #
  # This setting can be further reduced (but not increased) by using the inheritable per-class
  # job_iteration_max_job_runtime setting.
  # @example
  #
  #   class MyJob < ActiveJob::Base
  #     include JobIteration::Iteration
  #     self.job_iteration_max_job_runtime = 1.minute
  #     # ...
  attr_accessor :max_job_runtime

  # Configures a delay duration to wait before resuming an interrupted job.
  # @example
  #
  #   JobIteration.default_retry_backoff = 10.seconds
  #
  # Defaults to nil which means interrupted jobs will be retried immediately.
  # This value will be ignored when an interruption is raised by a throttle enumerator,
  # where the throttle backoff value will take precedence over this setting.
  attr_accessor :default_retry_backoff

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
end
