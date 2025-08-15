# frozen_string_literal: true

require "test_helper"

module JobIteration
  class NestedEnumeratorTest < IterationUnitTest
    test "accepts only callables as enums" do
      error = assert_raises(ArgumentError) do
        build_enumerator(outer: [[1, 2, 3].each])
      end
      assert_equal("enums must contain only procs/lambdas", error.message)
    end

    test "raises when cursor is not of the same size as enums" do
      error = assert_raises(ArgumentError) do
        build_enumerator(cursor: [Product.first.id])
      end
      assert_equal("cursor should have one object per enum", error.message)
    end

    test "raises when first level returns non-enumerable" do
      error = assert_raises(NestedEnumerator::InvalidNestedEnumeratorError) do
        build_enumerator(outer: ->(_) { nil }).each_with_index {}
      end
      assert_equal(
        "Expected an Enumerator object, but returned NilClass at index 0",
        error.message,
      )
    end

    test "raises when inner level returns non-enumerable" do
      error = assert_raises(NestedEnumerator::InvalidNestedEnumeratorError) do
        build_enumerator(inner: ->(_, _) { nil }).each_with_index {}
      end
      assert_equal(
        "Expected an Enumerator object, but returned NilClass at index 1",
        error.message,
      )
    end

    test "yields enumerator when called without a block" do
      enum = build_enumerator
      assert enum.is_a?(Enumerator)
      assert_nil enum.size
    end

    test "yields every nested record with their cursor position" do
      enum = build_enumerator

      products = Product.includes(:comments).order(:id).take(3)
      comments = products.flat_map { |product| product.comments.sort_by(&:id) }
      cursors = [[nil, 1], [1, 2], [1, 3], [2, 4], [2, 5], [2, 6]]

      enum.each_with_index do |(comment, cursor), index|
        expected_comment = comments[index]
        expected_cursor = cursors[index]
        assert_equal(expected_comment, comment)
        assert_equal(expected_cursor, cursor)
      end
    end

    test "cursor can be used to resume" do
      enum = build_enumerator
      _first_comment, first_cursor = enum.next
      second_comment, second_cursor = enum.next

      enum = build_enumerator(cursor: first_cursor)
      assert_equal([second_comment, second_cursor], enum.first)
    end

    test "doesn't yield anything if contains empty enum" do
      enum = ->(cursor, _product) { records_enumerator(Comment.none, cursor: cursor) }
      enum = build_enumerator(inner: enum)
      assert_empty(enum.to_a)
    end

    test "works with single level nesting" do
      enum = build_enumerator(inner: nil)
      products = Product.order(:id).to_a
      cursors = (1..10).to_a

      enum.each_with_index do |(product, cursor), index|
        assert_equal(products[index], product)
        assert_equal([cursors[index]], cursor)
      end
    end

    private

    def build_enumerator(
      outer: ->(cursor) { records_enumerator(Product.all, cursor: cursor) },
      inner: ->(product, cursor) { records_enumerator(product.comments, cursor: cursor) },
      cursor: nil
    )
      NestedEnumerator.new([outer, inner].compact, cursor: cursor).each
    end

    def records_enumerator(scope, cursor: nil)
      ActiveRecordEnumerator.new(scope, cursor: cursor).records
    end
  end
end
