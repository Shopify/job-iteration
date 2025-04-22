# frozen_string_literal: true

module JobIteration
  class BatchDeletingEnumerator
    include Enumerable

    def initialize(relation, batch_size:)
      @relation = relation
      @batch_size = batch_size
    end

    def each(&block)
      return to_enum unless block_given?

      while (relation = next_batch)
        yield relation, nil
      end
    end

    private

    def next_batch
      primary_keys = @relation
        .limit(@batch_size)
        .order(@relation.klass.primary_key)
        .pluck(*@relation.klass.primary_key)
        .to_a

      return if primary_keys.empty?

      primary_keys
    end

    class << self
      def delete_batch(relation, pk_values)
        where_in(relation, relation.klass.primary_key => pk_values).delete_all
      end

      def where_in(relation, attrs_and_values)
        attrs_and_values.reduce(relation) do |rel, (attrs, values)|
          next rel.none if values.empty? || attrs.empty?

          attrs = Array(attrs)
          statement = "(#{attrs.join(", ")}) IN (#{(["(?)"] * values.size).join(", ")})"
          sql = ActiveRecord::Base.sanitize_sql_array([statement, *values])
          rel.where(sql)
        end
      end
    end
  end
end
