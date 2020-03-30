module QueryParser
  class Visitor
    def visit(object, collector)
      dispatch_method = "visit_#{(object.class.name || '').gsub('::', '_')}"
      send dispatch_method, object, collector
    end

    def visit_Arel_Nodes_SelectStatement(o, collector)
      collector = o.cores.inject(collector) { |c, x|
        visit_Arel_Nodes_SelectCore(x, c)
      }

      # unless o.orders.empty?
      #   collector << " ORDER BY "
      #   o.orders.each_with_index do |x, i|
      #     collector << ", " unless i == 0
      #     collector = visit(x, collector)
      #   end
      # end
    end

    def visit_Arel_Nodes_SelectCore(o, collector)
      collector << "SELECT"

      # collector = collect_optimizer_hints(o, collector)
      # collector = maybe_visit o.set_quantifier, collector

      collect_nodes_for o.projections, collector, " "

      if o.source && !o.source.empty?
        collector << " FROM "
        collector = visit o.source, collector
      end

      collect_nodes_for o.wheres, collector, " WHERE ", " AND "
      collect_nodes_for o.groups, collector, " GROUP BY "
      collect_nodes_for o.havings, collector, " HAVING ", " AND "
      collect_nodes_for o.windows, collector, " WINDOW "

      # maybe_visit o.comment, collector
    end

    def visit_Arel_Nodes_Equality(o, collector)
      right = o.right

      return collector << "1=0" if unboundable?(right)

      collector = visit o.left, collector

      # binding.pry if $OMG
      collector.add_attribute_equality(o.left, o.right)

      if right.nil?
        collector << " IS NULL"
      else
        collector << " = "
        visit right, collector
      end
    end

    def unboundable?(value)
      value.respond_to?(:unboundable?) && value.unboundable?
    end

    def collect_nodes_for(nodes, collector, spacer, connector = ", ")
      unless nodes.empty?
        collector << spacer
        inject_join nodes, collector, connector
      end
    end

    def inject_join(list, collector, join_str)
      list.each_with_index do |x, i|
        collector << join_str unless i == 0
        collector = visit(x, collector)
      end
      collector
    end

    def visit_Arel_Attributes_Attribute(o, collector)
      join_name = o.relation.table_alias || o.relation.name
      collector << join_name << "." << o.name
      collector
    end
    alias :visit_Arel_Attributes_Integer :visit_Arel_Attributes_Attribute
    alias :visit_Arel_Attributes_Float :visit_Arel_Attributes_Attribute
    alias :visit_Arel_Attributes_Decimal :visit_Arel_Attributes_Attribute
    alias :visit_Arel_Attributes_String :visit_Arel_Attributes_Attribute
    alias :visit_Arel_Attributes_Time :visit_Arel_Attributes_Attribute
    alias :visit_Arel_Attributes_Boolean :visit_Arel_Attributes_Attribute

    def visit_Arel_Nodes_JoinSource(o, collector)
      if o.left
        collector = visit o.left, collector
      end
      if o.right.any?
        collector << " " if o.left
        collector = inject_join o.right, collector, " "
      end
      collector
    end

    def visit_Arel_Table(o, collector)
      if o.table_alias
        collector << quote_table_name(o.name) << " " << quote_table_name(o.table_alias)
      else
        collector << quote_table_name(o.name)
      end
    end

    def quote_table_name(name)
      name
    end

    def visit_Arel_Nodes_And(o, collector)
      inject_join o.children, collector, " AND "
    end

    def visit_Arel_Nodes_Grouping(o, collector)
      if o.expr.is_a? Arel::Nodes::Grouping
        visit(o.expr, collector)
      else
        collector << "("
        visit(o.expr, collector) << ")"
      end
    end

    def literal(o, collector)
      collector.add_literal_condition(o.to_s) # custom
      collector << o.to_s
    end

    def visit_Arel_Nodes_BindParam(o, collector)
      collector
      # collector.add_bind(o.value) { "?" }
    end

    alias :visit_Arel_Nodes_SqlLiteral :literal
    alias :visit_Integer               :literal

    def maybe_visit(thing, collector)
      return collector unless thing
      collector << " "
      visit thing, collector
    end

    def visit_Arel_Nodes_NotEqual(o, collector)
      right = o.right

      return collector << "1=1" if unboundable?(right)

      # collector.add_violation()
      # raise "not allowed"
      # TODO: do not allow this at all
      collector.add_violation("NOT is not allowed: #{o.left.name}")

      collector = visit o.left, collector

      if right.nil?
        collector << " IS NOT NULL"
      else
        collector << " != "
        visit right, collector
      end
    end

    def visit_Arel_Nodes_InfixOperation(o, collector)
      collector = visit o.left, collector
      collector << " #{o.operator} "
      visit o.right, collector
    end

    def visit_Arel_Nodes_In(o, collector)
      unless Array === o.right
        return collect_in_clause(o.left, o.right, collector)
      end

      unless o.right.empty?
        o.right.delete_if { |value| unboundable?(value) }
      end

      return collector << "1=0" if o.right.empty?

      in_clause_length = 10000

      collector.add_attribute_equality(o.left, o.right)

      if !in_clause_length || o.right.length <= in_clause_length
        collect_in_clause(o.left, o.right, collector)
      else
        collector << "("
        o.right.each_slice(in_clause_length).each_with_index do |right, i|
          collector << " OR " unless i == 0
          collect_in_clause(o.left, right, collector)
        end
        collector << ")"
      end
    end

    def collect_in_clause(left, right, collector)
      collector = visit left, collector
      collector << " IN ("
      visit(right, collector) << ")"
    end

    def visit_Array(o, collector)
      inject_join o, collector, ", "
    end
    alias :visit_Set :visit_Array

    def visit_Arel_Nodes_StringJoin(o, collector)
      visit o.left, collector
    end
  end
end
