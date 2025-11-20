# frozen_string_literal: true

module JobIteration
  class ActiveRecordBatchEnumerator
    # Utility class for the batch enumerator that manages the columns that need
    # to be plucked. It ensures primary key columns are plucked so that records
    # in the batch can be queried for efficiently.
    #
    # @see ActiveRecordBatchEnumerator
    class ColumnManager
      # @param relation [ActiveRecord::Relation] - relation to manage columns for
      # @param columns [Array<String,Symbol>, nil] - set of columns to select
      def initialize(relation:, columns:)
        @table_name = relation.table_name
        @primary_key = Array(relation.primary_key)
        @qualified_pkey_columns = @primary_key.map { |col| qualify_column(col) }
        @columns = columns&.map(&:to_s) || @qualified_pkey_columns

        validate_columns!(relation)
        initialize_pluck_columns_and_pkey_positions
      end

      # @return [Array<String>]
      #   The list of columns to be plucked. If no columns were specified, this
      #   list contains the fully qualified primary key column(s).
      attr_reader :columns

      # @return [Array<String>]
      #   The list of primary key columns for the relation. These columns are
      #   not qualified with the table name.
      attr_reader :primary_key

      # @return [Array<String>]
      #   The full set of columns to be plucked from the relation. This is a
      #   superset of `columns` and is guaranteed to contain all of the primary
      #   key columns on the relation.
      attr_reader :pluck_columns

      # @param column_values [Array<Array>]
      #   List of rows where each row contains values as determined by
      #   `pluck_columns`.
      #
      # @return [Array<Array>]
      #   List where each item contains the primary key column values for the
      #   corresponding row. Values are guaranteed to be in the same order as
      #   the columns are listed in `primary_key`.
      def pkey_values(column_values)
        column_values.map do |values|
          @qualified_pkey_columns.map do |pkey_column|
            pkey_column_idx = @primary_key_index_map[pkey_column]
            values[pkey_column_idx]
          end
        end
      end

      # @param cursor [Array]
      #   A list of values for a single row, as determined by `pluck_columns`.
      #
      # @return [Array]
      #   The same values that were passed in, minus any primary key column
      #   values that do not appear in `columns`.
      def remove_missing_pkey_values(cursor)
        cursor.pop(@missing_pkey_count)
        cursor
      end

      private

      def qualify_column(column)
        "#{@table_name}.#{column}"
      end

      def validate_columns!(relation)
        raise ArgumentError, "Must specify at least one column" if @columns.empty?

        if relation.joins_values.present? && !@columns.all? { |column| column.to_s.include?(".") }
          raise ArgumentError, "You need to specify fully-qualified columns if you join a table"
        end
      end

      # This method is responsible for initializing several instance variables:
      #
      # * `@pluck_columns` [Array<String>] -
      #       The set of columns to pluck.
      # * `@missing_pkey_count` [Integer] -
      #       The number of primary keys that were missing from `@columns`.
      # * `@primary_key_index_map` [Hash<String:Integer>] -
      #       Hash mapping all primary key columns to their position in
      #       `@pluck_columns`.
      def initialize_pluck_columns_and_pkey_positions
        @pluck_columns = @columns.dup
        initial_pkey_index_map = find_initial_primary_key_indices(@pluck_columns)

        missing_pkey_columns = initial_pkey_index_map.select { |_, idx| idx.nil? }.keys
        missing_pkey_index_map = add_missing_pkey_columns!(missing_pkey_columns, @pluck_columns)
        @missing_pkey_count = missing_pkey_index_map.size

        # Compute the location of each primary key column in `@pluck_columns`.
        @primary_key_index_map = initial_pkey_index_map.merge(missing_pkey_index_map)
      end

      # Figure out which primary key columns are already included in `columns`
      # and track their position in the array.
      #
      # @param column [Array<String>] - list of columns
      #
      # @return [Hash<String:Integer,nil>]
      #   A hash containing all of the fully qualified primary key columns as
      #   its keys. Values are the position of each column in the `columns`
      #   array. A `nil` value indicates the column is not present in `columns`.
      def find_initial_primary_key_indices(columns)
        @primary_key.each_with_object({}) do |pkey_column, indices|
          fully_qualified_pkey_column = qualify_column(pkey_column)
          idx = columns.index(pkey_column) || columns.index(fully_qualified_pkey_column)

          indices[fully_qualified_pkey_column] = idx
        end
      end

      # Takes a set of primary key columns and adds them to `columns`.
      #
      # @effect - mutates `columns`
      #
      # @param missing_columns [Array<String>] - set of missing pkey columns
      # @param columns [Array<String>] - set of columns to pluck
      #
      # @return [Hash<String:Integer>]
      #   A hash containing all of the values from `missing_columns` as its
      #   keys. Values are the position of those columns in `columns`.
      def add_missing_pkey_columns!(missing_columns, columns)
        missing_columns.each_with_object({}) do |pkey_column, indices|
          indices[pkey_column] = columns.size
          columns << pkey_column
        end
      end
    end
  end
end
