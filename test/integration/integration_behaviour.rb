# frozen_string_literal: true

module IntegrationBehaviour
  extend ActiveSupport::Concern

  included do
    setup do
      @original_adapter = ActiveJob::Base.queue_adapter
      ActiveJob::Base.queue_adapter = queue_adapter
    end

    teardown do
      ActiveJob::Base.queue_adapter = @original_adapter
    end

    test "interrupts the job" do
      IterationJob.perform_later

      start_worker_and_wait

      assert_equal 1, queue_size
      assert_equal 0, job_args.dig(0, "cursor_position")
      assert_equal 1, job_args.dig(0, "times_interrupted")

      start_worker_and_wait

      assert_equal 1, queue_size
      assert_equal 2, job_args.dig(0, "cursor_position")
      assert_equal 2, job_args.dig(0, "times_interrupted")

      TerminateJob.perform_later
      start_worker_and_wait

      assert_equal 0, queue_size
    end

    test "unserializable corruption is prevented" do
      skip "Breaking change deferred until 2.0" if Gem::Version.new(JobIteration::VERSION) < Gem::Version.new("2.0")
      # Cursors are serialized as JSON, but not all objects are serializable.
      #     time   = Time.at(0).utc   # => 1970-01-01 00:00:00 UTC
      #     json   = JSON.dump(time)  # => "\"1970-01-01 00:00:00 UTC\""
      #     string = JSON.parse(json) # => "1970-01-01 00:00:00 UTC"
      # We serialized a Time, but it was deserialized as a String.
      TimeCursorJob.perform_later
      TerminateJob.perform_later
      start_worker_and_wait

      assert_equal(
        JobIteration::Iteration::CursorError.name,
        failed_job_error_class_name,
      )
    end

    private

    # Should return the symbol to use when configuring the adapter
    #     ActiveJob::Base.queue_adapter = adapter
    def adapter
      raise NotImplemented, "#{self.class.name} must implement #{__method__}"
    end

    # Should start the job worker process and allow it to work the queue
    def start_worker_and_wait
      raise NotImplemented, "#{self.class.name} must implement #{__method__}"
    end

    # Should return the number of jobs currently enqueued for processing
    def queue_size
      raise NotImplemented, "#{self.class.name} must implement #{__method__}"
    end

    # Should return the hash of job arguments belonging to the most recently enqueued job
    def job_args
      raise NotImplemented, "#{self.class.name} must implement #{__method__}"
    end

    # Should return a String matching the name of the error class of the most recently failed job
    def failed_job_error_class_name
      raise NotImplemented, "#{self.class.name} must implement #{__method__}"
    end
  end
end
