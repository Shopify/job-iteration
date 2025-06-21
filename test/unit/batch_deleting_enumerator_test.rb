# frozen_string_literal: true

require "test_helper"
require "job-iteration/batch_deleting_enumerator"

module JobIteration
  class BatchDeletingEnumeratorTest < IterationUnitTest
    test "#each yields batches of primary keys" do
      enum = build_enumerator.each
      products = Product.order(:id).take(4)

      batch, _cursor = enum.next
      assert_equal products.map(&:id).first(2), batch

      JobIteration::BatchDeletingEnumerator.delete_batch(Product.all, batch)

      batch, _cursor = enum.next
      assert_equal products.map(&:id).last(2), batch
    end

    test "#each doesn't yield anything if the relation is empty" do
      enum = build_enumerator(relation: Product.none)

      assert_equal([], enum.to_a)
    end

    test "batch size is configurable" do
      enum = build_enumerator(batch_size: 4)
      products = Product.order(:id).take(4)

      assert_equal([products.map(&:id), nil], enum.first)
    end

    test "delete_batch class method deletes records by primary key" do
      products = Product.order(:id).take(2)
      primary_keys = products.map(&:id)

      BatchDeletingEnumerator.delete_batch(Product.all, primary_keys)

      assert_equal 0, Product.where(id: primary_keys).count
    end

    private

    def build_enumerator(relation: Product.all, batch_size: 2)
      BatchDeletingEnumerator.new(
        relation,
        batch_size: batch_size,
      )
    end
  end
end
