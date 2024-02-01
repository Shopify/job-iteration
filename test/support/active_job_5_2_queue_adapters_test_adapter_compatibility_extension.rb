# frozen_string_literal: true

active_job_5_2_still_supported = Gem
  .loaded_specs["job-iteration"]
  .dependencies.find { |gem| gem.name == "activejob" }
  .requirement.satisfied_by?(Gem::Version.new("5.2"))

raise <<~MSG unless active_job_5_2_still_supported
  Now that support for Active Job 5.2 has been dropped, this patch is no longer required.
  You should:
    - Delete this file (`#{Pathname.new(__FILE__).relative_path_from(File.join(__dir__, "../.."))}`)
    - Remove the corresponding `require_relative` from `test/test_helper.rb`
MSG

# Nothing to do if we're using Active Job 6.0 or later
return if Gem.loaded_specs.fetch("activejob").version >= Gem::Version.new("6.0")

module JobIteration
  # This module backports the 6.0 implementation of ActiveJob::QueueAdapters::TestAdapter#job_to_hash,
  # which includes the serialized job, plus the fields included in 5.2's version.
  # Without this, ActiveJob's deserialization fails when using the TestAdapter, and our tests erroneously fail.
  module ActiveJob52QueueAdaptersTestAdapterCompatibilityExtension
    private

    def job_to_hash(job, extras = {})
      job.serialize.tap do |job_data|
        job_data[:job] = job.class
        job_data[:args] = job_data.fetch("arguments")
        job_data[:queue] = job_data.fetch("queue_name")
      end.merge(extras)
    end
  end
end

ActiveJob::QueueAdapters::TestAdapter.prepend(JobIteration::ActiveJob52QueueAdaptersTestAdapterCompatibilityExtension)
