# frozen_string_literal: true

module JobIteration
  class ActiveRecordNestedRecordsEnumerator
    include Enumerable

    def initialize(relations, columns: nil, batch_size: 100, cursor: nil)
      assert_relations!(relations)

      @relations = relations
      @columns = columns
      @batch_size = batch_size

      @cursor = cursor || Array.new(relations.size)
    end

    def each
      return to_enum unless block_given?

      iterate_nested_records do |record, cursor_value|
        yield record, cursor_value.dup
      end
    end

    private

    def assert_relations!(relations)
      if !relations.is_a?(Array) || relations.empty?
        raise ArgumentError, "relations must be a non-empty Array"
      end

      first_relation, *rest_relations = relations

      unless first_relation.is_a?(ActiveRecord::Relation)
        raise ArgumentError, "first relation must be an ActiveRecord::Relation"
      end

      unless rest_relations.all?(Proc)
        raise ArgumentError, "all child relations must be Procs"
      end
    end

    def iterate_nested_records(index = 0, records = [], cursor_values = [])
      relation = @relations[index]
      is_innermost = @relations.last == relation
      relation = relation.call(*records) if relation.is_a?(Proc)
      unless relation.is_a?(ActiveRecord::Relation)
        raise ArgumentError, "all child relations must be ActiveRecord::Relations"
      end

      cursor = @cursor[index]

      options = { batch_size: @batch_size }
      if is_innermost
        options[:columns] = @columns
      else
        # When running for the first time (no interruptions before), the cursor is nil.
        # For subsequent runs we need to reiterate the same parent records.
        options[:cursor_inclusive] = !cursor.nil?
      end

      ActiveRecordEnumerator.new(relation, cursor: cursor, **options).records.each do |record, cursor_value|
        cursor_values.push(cursor_value)

        if is_innermost
          yield(record, cursor_values)
        else
          records.push(record)
          iterate_nested_records(index + 1, records, cursor_values) do |*args|
            yield(*args)
          end
          records.pop
        end

        cursor_values.pop
      end
    end
  end
end
