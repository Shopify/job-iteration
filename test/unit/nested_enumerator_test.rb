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

    test "empty enumerator resets later cursor state" do
      outer = [10, 20, 30]
      middle = [1, 2, 3]
      inner = [:a, :b, :c]

      # next- 20, 2, :b
      cursor = [0, 0, 0]
      short_circuit = false

      enums = [
        ->(cursor) { enumerator_builder.build_array_enumerator(outer, cursor: cursor) },
        ->(outer_item, cursor) {
          if outer_item == 20 && short_circuit
            enumerator_builder.build_array_enumerator([], cursor: cursor)
          else
            enumerator_builder.build_array_enumerator(middle, cursor: cursor)
          end
        },
        ->(outer_item, middle_item, cursor) {
          v = inner.map { |i| [outer_item, middle_item, i] }
          enumerator_builder.build_array_enumerator(v, cursor: cursor)
        },
      ]

      enum = NestedEnumerator.new(enums, cursor: cursor).each
      value_and_cursor = enum.take(1)[0]
      assert_equal([[20, 2, :b], [0, 0, 1]], value_and_cursor)

      # next would normally be [20, 2, :c] but we short-circuit 20 and don't finish iterating over it so next should be [30, 1, :a].
      # however, because the inner cursor state isn't reset, next actually is [30, 1, :c] - :a and :b are skipped
      short_circuit = true
      enum = NestedEnumerator.new(enums, cursor: value_and_cursor[1]).each
      value_and_cursor = enum.take(1)[0]
      assert_equal([[30, 1, :a], [1, nil, 2]], value_and_cursor)
    end

    test "nested cursors depend on outer values" do
      outer = [10, 20, 30]
      middle = [1, 2, 3]
      inner = [:a, :b, :c]

      # next- [20, 2, :b]
      cursor = [0, 0, 0]

      enums = [
        ->(cursor) { enumerator_builder.build_array_enumerator(outer, cursor: cursor) },
        ->(_outer_item, cursor) { enumerator_builder.build_array_enumerator(middle, cursor: cursor) },
        ->(outer_item, middle_item, cursor) {
          v = inner.map { |i| [outer_item, middle_item, i] }
          enumerator_builder.build_array_enumerator(v, cursor: cursor)
        },
      ]

      enum = NestedEnumerator.new(enums, cursor: cursor).each
      value_and_cursor = enum.take(1)[0]
      assert_equal([[20, 2, :b], [0, 0, 1]], value_and_cursor)

      # next should be [20, 2, :c] but we insert a new item in between so next is [15, 2, :c].
      # an argument could be made that next should be [15, 1, :a]
      outer = [10, 15, 20, 30]
      enum = NestedEnumerator.new(enums, cursor: value_and_cursor[1]).each
      value_and_cursor = enum.take(1)[0]
      assert_equal([[20, 2, :c], [0, 0, 2]], value_and_cursor)
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

    def enumerator_builder
      EnumeratorBuilder.new(nil)
    end
  end
end
