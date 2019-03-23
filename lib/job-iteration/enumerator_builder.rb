# frozen_string_literal: true
require_relative "./active_record_enumerator"
require_relative "./csv_enumerator"
require "forwardable"

module JobIteration
  class EnumeratorBuilder
    extend Forwardable

    # These wrappers ensure we have a custom type that we can assert on in
    # Iteration. It's useful that the `wrapper` passed to EnumeratorBuilder in
    # `enumerator_builder` is _always_ the type that is returned from
    # `build_enumerator`. This prevents people from implementing custom
    # Enumerators without wrapping them in
    # `enumerator_builder.wrap(custom_enum)`. We don't do this yet for backwards
    # compatibility with raw calls to EnumeratorBuilder. Think of these wrappers
    # the way you should a middleware.
    class Wrapper < Enumerator
      def self.wrap(_builder, enum)
        new(-> { enum.size }) do |yielder|
          enum.each do |*val|
            yielder.yield(*val)
          end
        end
      end
    end

    def initialize(job, wrapper: Wrapper)
      @job = job
      @wrapper = wrapper
    end

    def_delegator :@wrapper, :wrap

    # Builds Enumerator objects that iterates once.
    def build_once_enumerator(cursor:)
      wrap(self, build_times_enumerator(1, cursor: cursor))
    end

    # Builds Enumerator objects that iterates N times and yields number starting from zero.
    def build_times_enumerator(number, cursor:)
      raise ArgumentError, "First argument must be an Integer" unless number.is_a?(Integer)
      wrap(self, build_array_enumerator(number.times.to_a, cursor: cursor))
    end

    # Builds Enumerator object from a given array, using +cursor+ as an offset.
    def build_array_enumerator(enumerable, cursor:)
      unless enumerable.is_a?(Array)
        raise ArgumentError, "enumerable must be an Array"
      end
      if enumerable.any? { |i| defined?(ActiveRecord) && i.is_a?(ActiveRecord::Base) }
        raise ArgumentError, "array cannot contain ActiveRecord objects"
      end
      drop =
        if cursor.nil?
          0
        else
          cursor + 1
        end

      wrap(self, enumerable.each_with_index.drop(drop).to_enum { enumerable.size })
    end

    # Builds Enumerator from a lock queue instance that belongs to a job.
    # The helper is only to be used from jobs that use LockQueue module.
    def build_lock_queue_enumerator(lock_queue, at_most_once:)
      unless lock_queue.is_a?(BackgroundQueue::LockQueue::RedisQueue) ||
          lock_queue.is_a?(BackgroundQueue::LockQueue::RolloutRedisQueue)
        raise ArgumentError, "an argument to #build_lock_queue_enumerator must be a LockQueue"
      end
      wrap(self, BackgroundQueue::LockQueueEnumerator.new(lock_queue, at_most_once: at_most_once).to_enum)
    end

    # Builds Enumerator from Active Record Relation. Each Enumerator tick moves the cursor one row forward.
    #
    # +columns:+ argument is used to build the actual query for iteration. +columns+: defaults to primary key:
    #
    #   1) SELECT * FROM users ORDER BY id LIMIT 100
    #
    # When iteration is resumed, +cursor:+ and +columns:+ values will be used to continue from the point
    # where iteration stopped:
    #
    #   2) SELECT * FROM users WHERE id > $CURSOR ORDER BY id LIMIT 100
    #
    # +columns:+ can also take more than one column. In that case, +cursor+ will contain serialized values
    # of all columns at the point where iteration stopped.
    #
    # Consider this example with +columns: [:created_at, :id]+. Here's the query will use on the first iteration:
    #
    #   1) SELECT * FROM `products` ORDER BY created_at, id LIMIT 100
    #
    # And the query on the next iteration:
    #
    #   2) SELECT * FROM `products`
    #        WHERE (created_at > '$LAST_CREATED_AT_CURSOR'
    #          OR (created_at = '$LAST_CREATED_AT_CURSOR' AND (id > '$LAST_ID_CURSOR')))
    #        ORDER BY created_at, id LIMIT 100
    def build_active_record_enumerator_on_records(scope, cursor:, **args)
      enum = build_active_record_enumerator(
        scope,
        cursor: cursor,
        **args
      ).records
      wrap(self, enum)
    end

    # Builds Enumerator from Active Record Relation and enumerates on batches.
    # Each Enumerator tick moves the cursor +batch_size+ rows forward.
    #
    # +batch_size:+ sets how many records will be fetched in one batch. Defaults to 100.
    #
    # For the rest of arguments, see documentation for #build_active_record_enumerator_on_records
    def build_active_record_enumerator_on_batches(scope, cursor:, **args)
      enum = build_active_record_enumerator(
        scope,
        cursor: cursor,
        **args
      ).batches
      wrap(self, enum)
    end

    alias_method :once, :build_once_enumerator
    alias_method :times, :build_times_enumerator
    alias_method :array, :build_array_enumerator
    alias_method :active_record_on_records, :build_active_record_enumerator_on_records
    alias_method :active_record_on_batches, :build_active_record_enumerator_on_batches

    private

    def build_active_record_enumerator(scope, cursor:, **args)
      unless scope.is_a?(ActiveRecord::Relation)
        raise ArgumentError, "scope must be an ActiveRecord::Relation"
      end

      JobIteration::ActiveRecordEnumerator.new(
        scope,
        cursor: cursor,
        **args
      )
    end
  end
end
