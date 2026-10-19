# typed: true
# frozen_string_literal: true

module JobIteration
  # ParallelEnumerator allows you to parallelize iterations.
  class ParallelEnumerator
    class EnqueueError < StandardError; end

    class EnqueueJobs
      def initialize(instances, tolerated_enqueue_errors: [])
        @instances = instances
        @tolerated_enqueue_errors = tolerated_enqueue_errors
      end

      attr_reader :instances, :tolerated_enqueue_errors

      def enqueue_jobs(job)
        child_jobs = instances.times.map do |index|
          job.class.new(*job.arguments).tap do |child_job|
            child_job.cursor_position = { "instance" => index, "instances" => instances, "inner_cursor" => nil }

            # Carry forward potential overrides from the parent job
            child_job.queue_name = job.queue_name
            child_job.priority = job.priority if job.priority
          end
        end

        ActiveJob.perform_all_later(child_jobs)

        failed_jobs = child_jobs.reject(&:successfully_enqueued?)
        return if failed_jobs.empty?

        skipped_jobs, failed_jobs = failed_jobs.partition { |child_job| tolerated?(child_job.enqueue_error) }
        instrument_skipped_jobs(job, skipped_jobs) if skipped_jobs.any?
        return if failed_jobs.empty?

        raise EnqueueError, "Failed to enqueue #{failed_jobs.size} out of #{instances} child jobs"
      end

      private

      def tolerated?(enqueue_error)
        tolerated_enqueue_errors.any? { |error_class| enqueue_error.is_a?(error_class) }
      end

      def instrument_skipped_jobs(job, skipped_jobs)
        ActiveSupport::Notifications.instrument(
          "skipped_parallel_jobs.iteration",
          job_class: job.class.name,
          instances: instances,
          skipped_instances: skipped_jobs.map { |child_job| child_job.cursor_position.fetch("instance") },
          enqueue_errors: skipped_jobs.map { |child_job| child_job.enqueue_error.class.name },
        )
      end
    end

    def initialize(block, cursor:)
      @instance = cursor["instance"]
      @instances = cursor["instances"]
      inner_cursor = cursor["inner_cursor"]
      @inner_enum = block.call(@instance, @instances, inner_cursor)
    end

    def to_enum
      Enumerator.new(-> { @inner_enum.size }) do |yielder|
        @inner_enum.each do |object_from_enumerator, cursor_from_enumerator|
          parallel_cursor = { "instance" => @instance, "instances" => @instances, "inner_cursor" => cursor_from_enumerator }
          yielder.yield(object_from_enumerator, parallel_cursor)
        end
      end
    end
  end
end
