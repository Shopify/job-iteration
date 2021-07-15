# frozen_string_literal: true

module JobIteration
  # Builds Batch Enumerator based on ActiveRecord Relation.
  # @see EnumeratorBuilder
  class ActiveRecordBatchEnumerator
    include Enumerable

    SQL_DATETIME_WITH_NSEC = "%Y-%m-%d %H:%M:%S.%N"

    def initialize(relation, columns: nil, batch_size: 100, cursor: nil)
      @batch_size = batch_size
      @primary_key = "#{relation.table_name}.#{relation.primary_key}"
      @columns = Array(columns&.map(&:to_s) || @primary_key)
      @primary_key_index = @columns.index(@primary_key) || @columns.index(relation.primary_key)
      @pluck_columns = if @primary_key_index
        @columns
      else
        @columns.dup << @primary_key
      end
      @cursor = Array.wrap(cursor)
      @initial_cursor = @cursor
      raise ArgumentError, "Must specify at least one column" if @columns.empty?
      if relation.joins_values.present? && !@columns.all? { |column| column.to_s.include?(".") }
        raise ArgumentError, "You need to specify fully-qualified columns if you join a table"
      end

      if relation.arel.orders.present? || relation.arel.taken.present?
        raise ConditionNotSupportedError
      end

      @base_relation = relation.reorder(@columns.join(","))
    end

    def each
      return to_enum { size } unless block_given?
      while (relation = next_batch)
        yield relation, cursor_value
      end
    end

    def size
      (@base_relation.count + @batch_size - 1) / @batch_size # ceiling division
    end

    private

    def next_batch
      relation = @base_relation.limit(@batch_size)
      if conditions.any?
        relation = relation.where(*conditions)
      end

      cursor_values, ids = relation.uncached do
        pluck_columns(relation)
      end

      cursor = cursor_values.last
      unless cursor.present?
        @cursor = @initial_cursor
        return
      end
      # The primary key was plucked, but original cursor did not include it, so we should remove it
      cursor.pop unless @primary_key_index
      @cursor = Array.wrap(cursor)

      # Yields relations by selecting the primary keys of records in the batch.
      # Post.where(published: nil) results in an enumerator of relations like: Post.where(ids: batch_of_ids)
      @base_relation.where(@primary_key => ids)
    end

    def pluck_columns(relation)
      if @pluck_columns.size == 1 # only the primary key
        column_values = relation.pluck(*@pluck_columns)
        return [column_values, column_values]
      end

      column_values = relation.pluck(*@pluck_columns)
      primary_key_index = @primary_key_index || -1
      primary_key_values = column_values.map { |values| values[primary_key_index] }

      serialize_column_values!(column_values)
      [column_values, primary_key_values]
    end

    def cursor_value
      return @cursor.first if @cursor.size == 1
      @cursor
    end

    def conditions
      column_index = @cursor.size - 1
      column = @columns[column_index]
      where_clause = if @columns.size == @cursor.size
        "#{column} > ?"
      else
        "#{column} >= ?"
      end
      while column_index > 0
        column_index -= 1
        column = @columns[column_index]
        where_clause = "#{column} > ? OR (#{column} = ? AND (#{where_clause}))"
      end
      ret = @cursor.reduce([where_clause]) { |params, value| params << value << value }
      ret.pop
      ret
    end

    def serialize_column_values!(column_values)
      column_values.map! { |values| values.map! { |value| column_value(value) } }
    end

    def column_value(value)
      value.is_a?(Time) ? value.strftime(SQL_DATETIME_WITH_NSEC) : value
    end
  end
end
