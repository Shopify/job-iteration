# frozen_string_literal: true

require "test_helper"

module JobIteration
  class ActiveRecordNestedRecordsEnumeratorTest < IterationUnitTest
    SQL_TIME_FORMAT = "%Y-%m-%d %H:%M:%S.%N"

    attr_reader :described_class

    setup do
      @described_class = JobIteration::ActiveRecordNestedRecordsEnumerator
    end

    test "#initialize raises if passed object is not Array" do
      error = assert_raises(ArgumentError) do
        described_class.new(:not_array)
      end
      assert_equal("relations must be a non-empty Array", error.to_s)
    end

    test "#initialize raises if passed object is an empty Array" do
      error = assert_raises(ArgumentError) do
        described_class.new([])
      end
      assert_equal("relations must be a non-empty Array", error.to_s)
    end

    test "#initialize raises if first relation is not an ActiveRecord::Relation" do
      error = assert_raises(ArgumentError) do
        described_class.new([:no_a_relation])
      end
      assert_equal("first relation must be an ActiveRecord::Relation", error.to_s)
    end

    test "#initialize raises if child relations are not Procs" do
      error = assert_raises(ArgumentError) do
        described_class.new([Product.all, :not_a_proc])
      end
      assert_equal("all child relations must be Procs", error.to_s)
    end

    test "#each with child relations yields every record with their cursor position" do
      enum = build_enumerator
      comment_tuples =
        Product.includes(:comments).order(:id).take(2)
          .map { |product| product.comments.sort_by(&:id).map { |comment| [comment, [product.id, comment.id]] } }
          .flatten(1)

      enum.first(6).each_with_index do |comment_tuple, index|
        assert_equal comment_tuples[index], comment_tuple
      end
    end

    test "#each without child relations yields every record with their cursor position" do
      enum = build_enumerator(relations: [Product.all])
      product_tuples = Product.order(:id).take(2).map { |product| [product, [product.id]] }

      enum.first(2).each_with_index do |product_tuple, index|
        assert_equal product_tuples[index], product_tuple
      end
    end

    test "#each doesn't yield anything if the first relation is empty" do
      enum = build_enumerator(relations: [Product.none])
      assert_equal([], enum.to_a)
    end

    test "#each doesn't yield anything if child relation is empty" do
      enum = build_enumerator(relations: [Product.all, ->(product) { product.comments.none }])
      assert_equal([], enum.to_a)
    end

    test "#each raises if child relation is not an ActiveRecord::Relation" do
      enum = build_enumerator(relations: [Product.all, ->(_product) { :not_a_relation }])
      error = assert_raises(ArgumentError) do
        enum.to_a
      end
      assert_equal("all child relations must be ActiveRecord::Relations", error.to_s)
    end

    test "#each yields enumerator when called without a block" do
      enum = build_enumerator.each
      assert enum.is_a?(Enumerator)
    end

    test "batch size is configurable" do
      enum = build_enumerator(relations: [Product.all, ->(product) { product.comments }], batch_size: 4)

      queries = track_queries do
        enum.to_a
      end
      expected_num_queries =
        3 + # to get products
        2 * 10 # to get comments for each product

      assert_equal(expected_num_queries, queries.size)
    end

    test "columns are configurable" do
      enum = build_enumerator(columns: [:updated_at])
      product = Product.first
      comment = product.comments.order(:updated_at).first

      assert_equal([comment, [product.id, comment.updated_at.strftime(SQL_TIME_FORMAT)]], enum.first)
    end

    test "columns can be an array" do
      enum = build_enumerator(columns: [:updated_at, :id])
      product = Product.first
      comment = product.comments.order(:updated_at, :id).first

      assert_equal([comment, [product.id, [comment.updated_at.strftime(SQL_TIME_FORMAT), product.id]]], enum.first)
    end

    test "cursor can be used to resume" do
      product = Product.first
      comments = product.comments.order(:id).take(2)

      enum = build_enumerator(cursor: [product.id, comments.first.id])

      assert_equal([comments.second, [product.id, comments.second.id]], enum.first)
    end

    test "cursor resumes on next record when previous was finished" do
      product1, product2 = Product.order(:id).take(2)

      enum = build_enumerator(cursor: [product1.id, product1.comments.order(:id).last.id])

      starting_comment = product2.comments.order(:id).first
      assert_equal([starting_comment, [product2.id, starting_comment.id]], enum.first)
    end

    private

    def build_enumerator(relations: nil, batch_size: 2, columns: nil, cursor: nil)
      relations ||= [Product.all, ->(product) { product.comments }]
      described_class.new(
        relations,
        cursor: cursor,
        columns: columns,
        batch_size: batch_size
      )
    end
  end
end
