# typed: true
# frozen_string_literal: true

module JobIteration
  # ParallelEnumerator allows you to parallelize iterations.
  class ParallelEnumerator
    class EnqueueError < StandardError; end

    class EnqueueJobs
      def initialize(instances)
        @instances = instances
      end

      attr_reader :instances

      def enqueue_jobs(job)
        child_jobs = instances.times.map do |index|
          job.class.new(*job.arguments).tap do |child_job|
            child_job.cursor_position = { "instance" => index, "inner_cursor" => nil }

            # Carry forward potential overrides from the parent job
            child_job.queue_name = job.queue_name
            child_job.priority = job.priority if job.priority
          end
        end

        ActiveJob.perform_all_later(child_jobs)

        unless child_jobs.all?(&:successfully_enqueued?)
          failed_count = instances - child_jobs.count(&:successfully_enqueued?)
          raise EnqueueError, "Failed to enqueue #{failed_count} out of #{instances} child jobs"
        end
      end
    end

    def initialize(block, instances:, cursor:)
      @instance = cursor["instance"]
      inner_cursor = cursor["inner_cursor"]
      @inner_enum = block.call(@instance, instances, inner_cursor)
    end

    def to_enum
      Enumerator.new(-> { @inner_enum.size }) do |yielder|
        @inner_enum.each do |object_from_enumerator, cursor_from_enumerator|
          parallel_cursor = { "instance" => @instance, "inner_cursor" => cursor_from_enumerator }
          yielder.yield(object_from_enumerator, parallel_cursor)
        end
      end
    end
  end
end
