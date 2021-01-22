# frozen_string_literal: true
require_relative "./active_record_cursor"
module JobIteration
  # Builds Enumerator based on ActiveRecord Relation. Supports enumerating on rows and batches.
  # @see EnumeratorBuilder
  class ActiveRecordEnumerator
    def initialize(relation, columns: nil, batch_size: 100, cursor: nil)
      @deferred_enumerator = DeferredActiveRecordEnumerator.new(
        relation,
        columns: columns,
        batch_size: batch_size,
      )
      @relation = relation
      @cursor = cursor
    end

    def records
      deferred_enumerator.records.call(cursor: cursor)
    end

    def batches
      deferred_enumerator.batches.call(cursor: cursor)
    end

    def size
      relation.count
    end

    private

    attr_reader :cursor
    attr_reader :deferred_enumerator
    attr_reader :relation
  end
end
