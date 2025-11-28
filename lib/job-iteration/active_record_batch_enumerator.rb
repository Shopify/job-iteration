# frozen_string_literal: true

require_relative "active_record_batch_enumerator/column_manager"

module JobIteration
  # Builds Batch Enumerator based on ActiveRecord Relation.
  # @see EnumeratorBuilder
  class ActiveRecordBatchEnumerator
    include Enumerable

    SQL_DATETIME_WITH_NSEC = "%Y-%m-%d %H:%M:%S.%N"

    def initialize(relation, columns: nil, batch_size: 100, timezone: nil, cursor: nil)
      @batch_size = batch_size
      @timezone = timezone
      @column_mgr = ColumnManager.new(relation: relation, columns: columns)
      @cursor = Array.wrap(cursor)
      @initial_cursor = @cursor

      if relation.arel.orders.present? || relation.arel.taken.present?
        raise JobIteration::ActiveRecordCursor::ConditionNotSupportedError
      end

      @base_relation = relation.reorder(@column_mgr.columns.join(","))
    end

    def each
      return to_enum { size } unless block_given?

      while (relation = next_batch)
        yield relation, cursor_value
      end
    end

    def size
      (@base_relation.count(:all) + @batch_size - 1) / @batch_size # ceiling division
    end

    private

    def next_batch
      relation = @base_relation.limit(@batch_size)
      if conditions.any?
        relation = relation.where(*conditions)
      end

      cursor_values, pkey_ids = relation.uncached do
        pluck_columns(relation)
      end

      cursor = cursor_values.last
      unless cursor.present?
        @cursor = @initial_cursor
        return
      end

      @cursor = @column_mgr.remove_missing_pkey_values(cursor)

      filter_relation_with_primary_key(pkey_ids)
    end

    # Yields relations by selecting the primary keys of records in the batch.
    # Post.where(published: nil) results in an enumerator of relations like:
    # Post.where(published: nil, ids: batch_of_ids)
    def filter_relation_with_primary_key(primary_key_values)
      pkey = @column_mgr.primary_key
      pkey_values = primary_key_values

      # If the primary key is only composed of a single column, simplify the
      # query. This keeps us compatible with Rails prior to 7.1 where composite
      # primary keys were introduced along with the syntax that allows you to
      # query for multi-column values.
      if pkey.size <= 1
        pkey = pkey.first
        pkey_values = pkey_values.map(&:first)
      end

      @base_relation.where(pkey => pkey_values)
    end

    def pluck_columns(relation)
      column_values = relation.pluck(*@column_mgr.pluck_columns)

      # Pluck behaves differently when only one column is given. By using zip,
      # we make the output consistent (at the cost of more object allocation).
      column_values = column_values.zip if @column_mgr.pluck_columns.size == 1

      primary_key_values = @column_mgr.pkey_values(column_values)

      serialize_column_values!(column_values)
      [column_values, primary_key_values]
    end

    def cursor_value
      return @cursor.first if @cursor.size == 1

      @cursor
    end

    def conditions
      column_index = @cursor.size - 1
      column = @column_mgr.columns[column_index]
      where_clause = if @column_mgr.columns.size == @cursor.size
        "#{column} > ?"
      else
        "#{column} >= ?"
      end
      while column_index > 0
        column_index -= 1
        column = @column_mgr.columns[column_index]
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
      return value unless value.is_a?(Time)

      value = value.in_time_zone(@timezone) unless @timezone.nil?
      value.strftime(SQL_DATETIME_WITH_NSEC)
    end
  end
end
