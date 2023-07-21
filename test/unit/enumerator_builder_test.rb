# frozen_string_literal: true

require "test_helper"
require "csv"

module JobIteration
  class EnumeratorBuilderTest < ActiveSupport::TestCase
    # Find all the methods that build enumerators
    methods = EnumeratorBuilder.instance_methods(false).reject do |method|
      method = EnumeratorBuilder.instance_method(method)
      # skip aliases
      method.name != method.original_name
    end

    define_singleton_method(:test_builder_method) do |builder_method, &block|
      test(".#{builder_method} wraps the enumerator", &block)
      # remove tested method
      methods.delete(builder_method)
    end

    test_builder_method(:wrap) do
      builder = enumerator_builder
      builder.wrap(builder, nil)
    end

    test_builder_method(:build_once_enumerator) do
      enumerator_builder(wraps: 3).build_once_enumerator(cursor: nil)
    end

    test_builder_method(:build_times_enumerator) do
      enumerator_builder(wraps: 2).build_times_enumerator(42, cursor: nil)
    end

    test_builder_method(:build_array_enumerator) do
      enumerator_builder.build_array_enumerator([42], cursor: nil)
    end

    test_builder_method(:build_active_record_enumerator_on_records) do
      enumerator_builder.build_active_record_enumerator_on_records(Product.all, cursor: nil)
    end

    test_builder_method(:build_active_record_enumerator_on_batches) do
      enumerator_builder.build_active_record_enumerator_on_batches(Product.all, cursor: nil)
    end

    test_builder_method(:build_active_record_enumerator_on_batch_relations) do
      enumerator_builder(wraps: 1).build_active_record_enumerator_on_batch_relations(Product.all, cursor: nil)
    end

    test_builder_method("build_active_record_enumerator_on_batch_relations without wrap") do
      enumerator_builder(wraps: 0)
        .build_active_record_enumerator_on_batch_relations(Product.all, cursor: nil, wrap: false)
    end

    test_builder_method(:build_throttle_enumerator) do
      enumerator_builder(wraps: 0).build_throttle_enumerator(nil, throttle_on: -> { false }, backoff: 1)
    end

    test_builder_method(:build_csv_enumerator) do
      enumerator_builder(wraps: 0).build_csv_enumerator(CSV.new("test"), cursor: nil)
    end

    test_builder_method(:build_nested_enumerator) do
      enumerator_builder(wraps: 0).build_nested_enumerator(
        [
          ->(cursor) {
            enumerator_builder.build_active_record_enumerator_on_records(Product.all, cursor: cursor)
          },
          ->(product, cursor) {
            enumerator_builder.build_active_record_enumerator_on_records(product.comments, cursor: cursor)
          },
        ],
        cursor: nil,
      )
    end

    # checks that all the non-alias methods were tested
    raise "methods not tested: #{methods.inspect}" unless methods.empty?

    test "#build_csv_enumerator uses the CsvEnumerator class" do
      csv = CSV.open(
        ["test", "support", "sample_csv_with_headers.csv"].join("/"),
        converters: :integer,
        headers: true,
      )
      builder = EnumeratorBuilder.new(mock, wrapper: mock)

      enum = builder.build_csv_enumerator(csv, cursor: nil)
      csv_rows = open_csv.map(&:fields)
      enum.each_with_index do |element_and_cursor, index|
        assert_equal [csv_rows[index], index], [element_and_cursor[0].fields, element_and_cursor[1]]
      end
    end

    private

    def enumerator_builder(wraps: 1)
      job = mock
      wrapper = mock
      builder = EnumeratorBuilder.new(job, wrapper: wrapper)
      wrapper.expects(:wrap).with(builder, anything).times(wraps)
      builder
    end

    def sample_csv_with_headers
      ["test", "support", "sample_csv_with_headers.csv"].join("/")
    end

    def open_csv(options = {})
      CSV.open(sample_csv_with_headers, converters: :integer, headers: true, **options)
    end
  end
end
