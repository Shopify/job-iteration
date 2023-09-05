# frozen_string_literal: true

require "test_helper"

class IntegrationsTest < IterationUnitTest
  class IterationJob < ActiveJob::Base
    include JobIteration::Iteration

    def build_enumerator(cursor:)
      enumerator_builder.build_once_enumerator(cursor: cursor)
    end

    def each_iteration(*)
    end
  end

  class ResqueJob < IterationJob
    self.queue_adapter = :resque
  end

  class SidekiqJob < IterationJob
    self.queue_adapter = :sidekiq
  end

  test "loads multiple integrations" do
    resque_job = ResqueJob.new.serialize
    ActiveJob::Base.execute(resque_job)

    sidekiq_job = SidekiqJob.new.serialize
    ActiveJob::Base.execute(sidekiq_job)
  end

  test ".register accepts an object does implementing #call" do
    JobIteration::Integrations.register(:registration_test, -> { true })

    assert(JobIteration::Integrations.registered_integrations[:registration_test].call)
  end

  test ".register raises when the callable object does not implement #call" do
    error = assert_raises(ArgumentError) do
      JobIteration::Integrations.register("foo", "bar")
    end
    assert_equal("Interruption adapter must respond to #call", error.message)
  end

  test "raises for unknown Active Job queue adapter names" do
    error = assert_raises(JobIteration::Integrations::LoadError) do
      JobIteration::Integrations.load("unknown")
    end
    assert_equal("Could not find integration for 'unknown'", error.message)
  end
end
