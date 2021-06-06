# frozen_string_literal: true
require_relative "./active_record_cursor"
module JobIteration
  # Builds Enumerator based on ActiveRecord Relation. Supports enumerating on rows and batches.
  # @see EnumeratorBuilder
  class ActiveRecordEnumerator
    SQL_DATETIME_WITH_NSEC = "%Y-%m-%d %H:%M:%S.%N"

    def initialize(relation, columns: nil, batch_size: 100, cursor: nil, cursor_inclusive: false)
      @relation = relation
      @batch_size = batch_size
      @columns = Array(columns || "#{relation.table_name}.#{relation.primary_key}")
      @cursor = cursor
      @cursor_inclusive = cursor_inclusive
    end

    def records
      Enumerator.new(method(:size)) do |yielder|
        batches.each do |batch, _|
          batch.each do |record|
            yielder.yield(record, cursor_value(record))
          end
        end
      end
    end

    def batches
      cursor = finder_cursor
      Enumerator.new(method(:size)) do |yielder|
        while (records = cursor.next_batch(@batch_size))
          yielder.yield(records, cursor_value(records.last)) if records.any?
        end
      end
    end

    def size
      @relation.count
    end

    private

    def cursor_value(record)
      positions = @columns.map do |column|
        attribute_name = column.to_s.split(".").last
        column_value(record, attribute_name)
      end
      return positions.first if positions.size == 1
      positions
    end

    def finder_cursor
      JobIteration::ActiveRecordCursor.new(@relation, @columns, @cursor, inclusive: @cursor_inclusive)
    end

    def column_value(record, attribute)
      value = record.read_attribute(attribute.to_sym)
      case record.class.columns_hash.fetch(attribute).type
      when :datetime
        value.strftime(SQL_DATETIME_WITH_NSEC)
      else
        value
      end
    end
  end
end
