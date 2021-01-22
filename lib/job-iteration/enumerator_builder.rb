# frozen_string_literal: true
require_relative "./active_record_enumerator"
require_relative "./csv_enumerator"
require_relative "./throttle_enumerator"
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
      @deferred_enumerator_builder = DeferredEnumeratorBuilder.new(job)
    end

    def_delegator :@wrapper, :wrap

    # Builds Enumerator objects that iterates once.
    def build_once_enumerator(cursor:)
      enum = deferred_enumerator_builder.build_deferred_once_enumerator
        .call(cursor: cursor)

      wrap(self, enum)
    end

    # Builds Enumerator objects that iterates N times and yields number starting from zero.
    def build_times_enumerator(number, cursor:)
      enum = deferred_enumerator_builder.build_deferred_times_enumerator(number)
        .call(cursor: cursor)

      wrap(self, enum)
    end

    # Builds Enumerator object from a given array, using +cursor+ as an offset.
    def build_array_enumerator(enumerable, cursor:)
      enum = deferred_enumerator_builder.build_array_enumerator(enumerable)
        .call(cursor: cursor)

      wrap(self, enum)
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
      enum = deferred_enumerator_builder.build_deferred_active_record_enumerator_on_records(
        scope,
        **args
      ).call(cursor: cursor)
      wrap(self, enum)
    end

    # Builds Enumerator from Active Record Relation and enumerates on batches.
    # Each Enumerator tick moves the cursor +batch_size+ rows forward.
    #
    # +batch_size:+ sets how many records will be fetched in one batch. Defaults to 100.
    #
    # For the rest of arguments, see documentation for #build_active_record_enumerator_on_records
    def build_active_record_enumerator_on_batches(scope, cursor:, **args)
      enum = deferred_enumerator_builder.build_deferred_active_record_enumerator_on_batches(
        scope,
        **args
      ).call(cursor: cursor)
      wrap(self, enum)
    end

    # TODO: Revisit this one
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

    attr_reader :deferred_enumerator_builder
  end
end
