# frozen_string_literal: true

require_relative "active_record_batch_enumerator"
require_relative "active_record_enumerator"
require_relative "csv_enumerator"
require_relative "throttle_enumerator"
require_relative "nested_enumerator"
require "forwardable"

module JobIteration
  class EnumeratorBuilder
    extend Forwardable

    # These wrappers ensure we have a custom type that we can assert on in
    # Iteration. It's useful that the `wrapper` passed to EnumeratorBuilder in
    # `enumerator_builder` is _always_ the type that is returned from
    # `build_enumerator`. This prevents people from implementing custom
    # Enumerators without wrapping them in
    # `enumerator_builder.wrap(custom_enum)`. Think of these wrappers
    # the way you should a middleware.
    class Wrapper < Enumerator
      class << self
        def wrap(_builder, enum)
          new(-> { enum.size }) do |yielder|
            enum.each do |*val|
              yielder.yield(*val)
            end
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

      drop =
        if cursor.nil?
          0
        else
          cursor + 1
        end

      wrap(self, enumerable.each_with_index.drop(drop).to_enum { enumerable.size })
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
    #
    # As a result of this query pattern, if the values in these columns change for the records in scope during
    # iteration, they may be skipped or yielded multiple times depending on the nature of the update and the
    # cursor's value. If the value gets updated to a greater value than the cursor's value, it will get yielded
    # again. Similarly, if the value gets updated to a lesser value than the curor's value, it will get skipped.
    def build_active_record_enumerator_on_records(scope, cursor:, **args)
      enum = build_active_record_enumerator(
        scope,
        cursor: cursor,
        **args,
      ).records
      wrap(self, enum)
    end

    # Builds Enumerator from Active Record Relation and enumerates on batches of records.
    # Each Enumerator tick moves the cursor +batch_size+ rows forward.
    #
    # +batch_size:+ sets how many records will be fetched in one batch. Defaults to 100.
    #
    # For the rest of arguments, see documentation for #build_active_record_enumerator_on_records
    def build_active_record_enumerator_on_batches(scope, cursor:, **args)
      enum = build_active_record_enumerator(
        scope,
        cursor: cursor,
        **args,
      ).batches
      wrap(self, enum)
    end

    # Builds Enumerator from Active Record Relation and enumerates on batches, yielding Active Record Relations.
    # See documentation for #build_active_record_enumerator_on_batches.
    def build_active_record_enumerator_on_batch_relations(scope, wrap: true, cursor:, **args)
      enum = JobIteration::ActiveRecordBatchEnumerator.new(
        scope,
        cursor: cursor,
        **args,
      ).each
      enum = wrap(self, enum) if wrap
      enum
    end

    def build_throttle_enumerator(enumerable, throttle_on:, backoff:)
      enum = JobIteration::ThrottleEnumerator.new(
        enumerable,
        @job,
        throttle_on: throttle_on,
        backoff: backoff,
      ).to_enum
      wrap(self, enum)
    end

    def build_csv_enumerator(enumerable, cursor:)
      enum = CsvEnumerator.new(enumerable).rows(cursor: cursor)
      wrap(self, enum)
    end

    def build_csv_enumerator_on_batches(enumerable, cursor:, batch_size: 100)
      enum = CsvEnumerator.new(enumerable).batches(cursor: cursor, batch_size: batch_size)
      wrap(self, enum)
    end

    # Builds Enumerator for nested iteration.
    #
    # @param enums [Array<Proc>] an Array of Procs, each should return an Enumerator.
    #   Each proc from enums should accept the yielded items from the parent enumerators
    #     and the `cursor` as its arguments.
    #   Each proc's `cursor` argument is its part from the `build_enumerator`'s `cursor` array.
    # @param cursor [Array<Object>] array of offsets for each of the enums to start iteration from
    #
    # @example
    #   def build_enumerator(cursor:)
    #     enumerator_builder.nested(
    #       [
    #         ->(cursor) {
    #           enumerator_builder.active_record_on_records(Shop.all, cursor: cursor)
    #         },
    #         ->(shop, cursor) {
    #           enumerator_builder.active_record_on_records(shop.products, cursor: cursor)
    #         },
    #         ->(_shop, product, cursor) {
    #           enumerator_builder.active_record_on_batch_relations(product.product_variants, cursor: cursor)
    #         }
    #       ],
    #       cursor: cursor
    #     )
    #   end
    #
    #   def each_iteration(product_variants_relation)
    #     # do something
    #   end
    #
    def build_nested_enumerator(enums, cursor:)
      enum = NestedEnumerator.new(enums, cursor: cursor).each
      wrap(self, enum)
    end

    alias_method :once, :build_once_enumerator
    alias_method :times, :build_times_enumerator
    alias_method :array, :build_array_enumerator
    alias_method :active_record_on_records, :build_active_record_enumerator_on_records
    alias_method :active_record_on_batches, :build_active_record_enumerator_on_batches
    alias_method :active_record_on_batch_relations, :build_active_record_enumerator_on_batch_relations
    alias_method :throttle, :build_throttle_enumerator
    alias_method :csv, :build_csv_enumerator
    alias_method :csv_on_batches, :build_csv_enumerator_on_batches
    alias_method :nested, :build_nested_enumerator

    private

    def build_active_record_enumerator(scope, cursor:, **args)
      unless scope.is_a?(ActiveRecord::Relation)
        raise ArgumentError, "scope must be an ActiveRecord::Relation"
      end

      JobIteration::ActiveRecordEnumerator.new(
        scope,
        cursor: cursor,
        **args,
      )
    end
  end
end
