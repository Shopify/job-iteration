# frozen_string_literal: true

require "test_helper"

module JobIteration
  class ActiveRecordEnumeratorTest < IterationUnitTest
    SQL_TIME_FORMAT = "%Y-%m-%d %H:%M:%S.%N"
    test "#records yields every record with their cursor position" do
      enum = build_enumerator.records
      shop_id_tuples = Product.all.order(:id).take(3).map { |shop| [shop, shop.id] }
      assert_equal Product.all.count, enum.size
      enum.first(3).each_with_index do |shop_id, index|
        assert_equal shop_id_tuples[index], shop_id
      end
    end

    test "#records doesn't yield anything if the relation is empty" do
      enum = build_enumerator(relation: Product.none).records

      assert_equal([], enum.to_a)
      assert_equal 0, enum.size
    end

    test "#batches yeilds batches of records with the last record's cursor position" do
      enum = build_enumerator.batches
      shop_id_tuples =
        Product.order(:id).take(4).in_groups_of(2).map { |shops| [shops, shops.last.id] }

      enum.first(2).each_with_index do |shop_id, index|
        assert_equal shop_id_tuples[index], shop_id
      end
    end

    test "#batches doesn't yield anything if the relation is empty" do
      enum = build_enumerator(relation: Product.none).batches

      assert_equal([], enum.to_a)
    end

    test "#batches continues iterating until ActiveRecordCursor returns nil" do
      shops = [Product.first, Product.last]
      JobIteration::ActiveRecordCursor
        .any_instance
        .stubs(:next_batch)
        .returns([shops[0]], [], [shops[1]], nil)

      enum = build_enumerator.batches
      enum.each_with_index do |batch, index|
        assert_equal [[shops[index]], shops[index].id], batch
      end
    end

    test "batch size is configurable" do
      enum = build_enumerator(batch_size: 4).batches
      shops = Product.order(:id).take(4)

      assert_equal([shops, shops.last.id], enum.first)
    end

    test "columns are configurable" do
      enum = build_enumerator(columns: [:updated_at]).batches
      shops = Product.order(:updated_at).take(2)

      assert_equal([shops, shops.last.updated_at.strftime(SQL_TIME_FORMAT)], enum.first)
    end

    test "columns can be an array" do
      enum = build_enumerator(columns: [:updated_at, :id]).batches
      shops = Product.order(:updated_at, :id).take(2)

      assert_equal([shops, [shops.last.updated_at.strftime(SQL_TIME_FORMAT), shops.last.id]], enum.first)
    end

    test "cursor can be used to resume" do
      shops = Product.order(:id).take(3)

      enum = build_enumerator(cursor: shops.shift.id).batches

      assert_equal([shops, shops.last.id], enum.first)
    end

    test "cursor can be used to resume on multiple columns" do
      enum = build_enumerator(columns: [:created_at, :id]).batches
      shops = Product.order(:created_at, :id).take(2)

      cursor = [shops.last.created_at.strftime(SQL_TIME_FORMAT), shops.last.id]
      assert_equal([shops, cursor], enum.first)

      enum = build_enumerator(columns: [:created_at, :id], cursor: cursor).batches
      shops = Product.order(:created_at, :id).offset(2).take(2)

      cursor = [shops.last.created_at.strftime(SQL_TIME_FORMAT), shops.last.id]
      assert_equal([shops, cursor], enum.first)
    end

    test "#size returns the number of items in the relation" do
      enum = build_enumerator(relation: Product.all)

      assert_equal(10, enum.size)
    end

    test "#size returns the number of items in a relation with a subset of columns" do
      enum = build_enumerator(relation: Product.select(:id, :name), columns: [:id, :name])

      assert_equal(10, enum.size)
    end

    private

    def build_enumerator(relation: Product.all, batch_size: 2, columns: nil, cursor: nil)
      JobIteration::ActiveRecordEnumerator.new(
        relation,
        batch_size: batch_size,
        columns: columns,
        cursor: cursor,
      )
    end
  end
end
