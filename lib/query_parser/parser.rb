module QueryParser
  class ResultWithViolations
    attr_reader :relation, :violations
    def initialize(relation, violations)
      @relation = relation
      @violations = violations
    end
  end

  class ResultWithColumns
    attr_reader :relation, :columns
    def initialize(relation, columns)
      @relation = relation
      @columns = columns
    end
  end

  module Parser
    extend self

    def parse(relation)
      collector = Collector.new

      Visitor.new.visit(relation.arel.ast, collector)

      if collector.violations.any?
        ResultWithViolations.new(relation, collector.violations)
      else
        ResultWithColumns.new(relation, collector.columns)
      end
    end
  end
end