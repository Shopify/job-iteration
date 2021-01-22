# frozen_string_literal: true
require_relative "./active_record_cursor"
module JobIteration
  # Builds Enumerator based on ActiveRecord Relation. Supports enumerating on rows and batches.
  # @see EnumeratorBuilder
  class DeferredActiveRecordEnumerator
    SQL_DATETIME_WITH_NSEC = "%Y-%m-%d %H:%M:%S.%N"

    def initialize(relation, columns: nil, batch_size: 100)
      @relation = relation
      @batch_size = batch_size
      @columns = Array(columns || "#{relation.table_name}.#{relation.primary_key}")
    end

    def records
      lambda do |cursor:|
        Enumerator.new(method(:size)) do |yielder|
          batches(cursor: cursor).each do |batch, _|
            batch.each do |record|
              yielder.yield(record, cursor_value(record))
            end
          end
        end
      end
    end

    def batches
      lambda do |cursor:|
        current_cursor = finder_cursor(cursor)
        Enumerator.new(method(:size)) do |yielder|
          while (records = current_cursor.next_batch(@batch_size))
            yielder.yield(records, cursor_value(records.last)) if records.any?
          end
        end
      end
    end

    private

    def size
      @relation.count
    end

    def cursor_value(record)
      positions = @columns.map do |column|
        attribute_name = column.to_s.split('.').last
        column_value(record, attribute_name)
      end
      return positions.first if positions.size == 1
      positions
    end

    def finder_cursor(cursor)
      JobIteration::ActiveRecordCursor.new(@relation, @columns, cursor)
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
