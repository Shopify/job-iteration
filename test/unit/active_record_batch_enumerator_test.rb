# frozen_string_literal: true

require "test_helper"

module JobIteration
  class ActiveRecordBatchEnumeratorTest < IterationUnitTest
    SQL_TIME_FORMAT = "%Y-%m-%d %H:%M:%S.%N"
    test "#each yields batches as relation with the last record's cursor position" do
      enum = build_enumerator
      product_batches = Product.order(:id).take(4).in_groups_of(2).map { |product| [product, product.last.id] }

      enum.first(2).each_with_index do |(batch, cursor), index|
        assert batch.is_a?(ActiveRecord::Relation)
        assert_equal product_batches[index].first, batch
        assert_equal product_batches[index].last, cursor
      end
    end

    test "#each yields relations repeatedly" do
      enum = build_enumerator(cursor: 2)
      assert_equal 4, enum.to_a.size
      assert_equal 4, enum.to_a.size
    end

    test "#each yields unloaded relations" do
      enum = build_enumerator
      relation, _ = enum.first

      refute_predicate relation, :loaded?
    end

    test "#each yields relations that preserve the existing conditions (like ActiveRecord::Batches)" do
      enum = build_enumerator(relation: Product.where("name LIKE 'lipstick%'"))
      relation, _ = enum.first
      assert_includes relation.to_sql, "lipstick"
    end

    test "#each yields enumerator when called without a block" do
      enum = build_enumerator.each
      assert enum.is_a?(Enumerator)
      assert_not_nil enum.size
    end

    test "#each doesn't yield anything if the relation is empty" do
      enum = build_enumerator(relation: Product.none)

      assert_equal([], enum.to_a)
    end

    test "#size returns size of the Enumerator" do
      enum = build_enumerator
      assert_equal 5, enum.size # 5 batches of 2
      enum = build_enumerator(batch_size: 3)
      assert_equal 4, enum.size # 3 batches of 3, 1 batch of 1
    end

    test "#size returns size of the Enumerator with a subset of columns" do
      enum = build_enumerator(relation: Product.select(:id, :name))
      assert_equal 5, enum.size # 5 batches of 2
      enum = build_enumerator(relation: Product.select(:id, :name), batch_size: 3)
      assert_equal 4, enum.size # 3 batches of 3, 1 batch of 1
    end

    test "batch size is configurable" do
      enum = build_enumerator(batch_size: 4)
      products = Product.order(:id).take(4)

      assert_equal([products, products.last.id], enum.first)
    end

    test "columns are configurable" do
      enum = build_enumerator(columns: [:updated_at])
      products = Product.order(:updated_at).take(2)

      expected_product_cursor = products.last.updated_at.utc.strftime(SQL_TIME_FORMAT)
      assert_equal([products, expected_product_cursor], enum.first)
    end

    test "columns can be an array" do
      enum = build_enumerator(columns: [:updated_at, :id])
      products = Product.order(:updated_at, :id).take(2)

      expected_product_cursor = [products.last.updated_at.utc.strftime(SQL_TIME_FORMAT), products.last.id]
      assert_equal([products, expected_product_cursor], enum.first)
    end

    test "columns configured with primary key only queries primary key column once" do
      queries = track_queries do
        enum = build_enumerator(columns: [:updated_at, :id])
        enum.first
      end
      assert_match(/\A\s?`products`.`updated_at`, `products`.`id`\z/, queries.first[/SELECT (.*) FROM/, 1])
    end

    test "columns use UTC during serialization if they are Time" do
      enum = build_enumerator(columns: [:updated_at])
      products = Product.order(:updated_at).take(2)

      expected_product_cursor = products.last.updated_at.utc.strftime(SQL_TIME_FORMAT)
      assert_equal([products, expected_product_cursor], enum.first)
    end

    test "cursor can be used to resume" do
      products = Product.order(:id).take(3)

      enum = build_enumerator(cursor: products.shift.id)

      assert_equal([products, products.last.id], enum.first)
    end

    test "cursor can be used to resume on multiple columns" do
      enum = build_enumerator(columns: [:created_at, :id])
      products = Product.order(:created_at, :id).take(2)

      cursor = [products.last.created_at.utc.strftime(SQL_TIME_FORMAT), products.last.id]
      assert_equal([products, cursor], enum.first)

      enum = build_enumerator(columns: [:created_at, :id], cursor: cursor)
      products = Product.order(:created_at, :id).offset(2).take(2)

      cursor = [products.last.created_at.utc.strftime(SQL_TIME_FORMAT), products.last.id]
      assert_equal([products, cursor], enum.first)
    end

    test "one query performed per batch, plus an additional one for the empty cursor" do
      enum = build_enumerator
      num_batches = 0
      queries = track_queries do
        enum.each { num_batches += 1 }
      end

      expected_num_queries = num_batches + 1
      assert_equal expected_num_queries, queries.size
    end

    test "enumerator will raise ConditionNotSupportedError if the relation is ordered" do
      assert_raise(JobIteration::ActiveRecordCursor::ConditionNotSupportedError) do
        build_enumerator(relation: Product.order(created_at: :desc))
      end
    end

    private

    def build_enumerator(relation: Product.all, batch_size: 2, columns: nil, cursor: nil)
      JobIteration::ActiveRecordBatchEnumerator.new(
        relation,
        batch_size: batch_size,
        columns: columns,
        cursor: cursor,
      )
    end

    def track_queries(&block)
      queries = []
      query_cb = ->(*, payload) { queries << payload[:sql] }
      ActiveSupport::Notifications.subscribed(query_cb, "sql.active_record", &block)
      queries
    end
  end
end
