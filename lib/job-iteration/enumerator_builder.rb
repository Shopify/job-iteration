# frozen_string_literal: true
require_relative "./active_record_enumerator"
require_relative "./csv_enumerator"
require_relative "./throttle_enumerator"

module JobIteration
  class EnumeratorBuilder
    def initialize(job)
      @job = job
    end

    # Builds Enumerator objects that iterates once.
    def build_once_enumerator(cursor:)
      build_times_enumerator(1, cursor: cursor)
    end

    # Builds Enumerator objects that iterates N times and yields number starting from zero.
    def build_times_enumerator(number, cursor:)
      raise ArgumentError, "First argument must be an Integer" unless number.is_a?(Integer)
      build_array_enumerator(number.times.to_a, cursor: cursor)
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

      enumerable.each_with_index.drop(drop).to_enum { enumerable.size }
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
      build_active_record_enumerator(
        scope,
        cursor: cursor,
        **args
      ).records
    end

    # Builds Enumerator from Active Record Relation and enumerates on batches.
    # Each Enumerator tick moves the cursor +batch_size+ rows forward.
    #
    # +batch_size:+ sets how many records will be fetched in one batch. Defaults to 100.
    #
    # For the rest of arguments, see documentation for #build_active_record_enumerator_on_records
    def build_active_record_enumerator_on_batches(scope, cursor:, **args)
      build_active_record_enumerator(
        scope,
        cursor: cursor,
        **args
      ).batches
    end

    def build_throttle_enumerator(enum, throttle_on:, backoff:)
      JobIteration::ThrottleEnumerator.new(
        enum,
        @job,
        throttle_on: throttle_on,
        backoff: backoff
      ).to_enum
    end

    alias_method :once, :build_once_enumerator
    alias_method :times, :build_times_enumerator
    alias_method :array, :build_array_enumerator
    alias_method :active_record_on_records, :build_active_record_enumerator_on_records
    alias_method :active_record_on_batches, :build_active_record_enumerator_on_batches
    alias_method :throttle, :build_throttle_enumerator

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
