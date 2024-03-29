# frozen_string_literal: true

module JobIteration
  # Curious about how this works from the SQL perspective?
  # Check "Pagination Done the Right way": https://bit.ly/2Rq7iPF
  class ActiveRecordCursor # @private
    include Comparable

    attr_reader :position
    attr_accessor :reached_end

    class ConditionNotSupportedError < ArgumentError
      def initialize
        super(
          "The relation cannot use ORDER BY or LIMIT due to the way how iteration with a cursor is designed. " \
            "You can use other ways to limit the number of rows, e.g. a WHERE condition on the primary key column."
        )
      end
    end

    def initialize(relation, columns, position = nil)
      @columns = columns
      self.position = Array.wrap(position)
      raise ArgumentError, "Must specify at least one column" if columns.empty?
      if relation.joins_values.present? && !@columns.all? { |column| column.is_a?(Arel::Attributes::Attribute) || column.to_s.include?(".") }
        raise ArgumentError, "You need to specify fully-qualified columns if you join a table"
      end

      if relation.arel.orders.present? || relation.arel.taken.present?
        raise ConditionNotSupportedError
      end

      @base_relation = relation.reorder(*@columns)
      @reached_end = false
    end

    def <=>(other)
      if reached_end != other.reached_end
        reached_end ? 1 : -1
      else
        position <=> other.position
      end
    end

    def position=(position)
      raise "Cursor position cannot contain nil values" if position.any?(&:nil?)

      @position = position
    end

    def update_from_record(record)
      self.position = @columns.map do |column|
        if ActiveRecord.version >= Gem::Version.new("7.1.0.alpha") && column.name == "id"
          record.id_value
        else
          record.send(column.name)
        end
      end
    end

    def next_batch(batch_size)
      return if @reached_end

      relation = @base_relation.limit(batch_size)

      if (conditions = self.conditions).any?
        relation = relation.where(*conditions)
      end

      records = relation.uncached do
        relation.to_a
      end

      update_from_record(records.last) unless records.empty?
      @reached_end = records.size < batch_size

      records.empty? ? nil : records
    end

    protected

    def conditions
      i = @position.size - 1
      column = @columns[i]
      conditions = if @columns.size == @position.size
        column.gt(@position[i])
      else
        column.gteq(@position[i])
      end
      while i > 0
        i -= 1
        column = @columns[i]
        conditions = column.gt(@position[i]).or(column.eq(@position[i]).and(conditions))
      end
      ret = @position.reduce([conditions]) { |params, value| params << value << value }
      ret.pop
      ret
    end
  end
end
