module QueryParser
  class Collector
    attr_reader :columns, :violations

    def initialize
      @string = +""
      @columns = []
      @violations = []
    end

    def <<(str)
      @string << str
      self
    end

    def add_violation(message)
      @violations << message
    end

    def add_attribute_equality(left, right)
      unless left.is_a?(Arel::Attributes::Attribute)
        raise "unknown left: #{left}"
      end

      # if right is nil, it means IS NULL
      @columns << left.name
    end

    def add_literal_condition(condition)
      if condition.match(/\s+OR\s+/i)
        add_violation("OR is not allowed: #{condition.inspect}")
        return
      end

      condition.split(/\s+and\s+/i).each do |tuple|
        values = tuple.split(/(=|<=|>=|>|<|\s+IN|\s+IS)/i)
        if values.size == 3
          column = values.first.strip
          @columns << column
        else
          raise "unexpected value for #{tuple}: #{values}"
        end
      end
    end
  end
end
