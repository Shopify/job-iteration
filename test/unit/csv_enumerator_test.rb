# frozen_string_literal: true
require 'test_helper'
require 'csv'

module JobIteration
  class CsvEnumeratorTest < ActiveSupport::TestCase
    test "#initialize raises if passed object is not CSV" do
      assert_raises(ArgumentError) do
        JobIteration::CsvEnumerator.new([])
      end

      assert_raises(ArgumentError) do
        JobIteration::CsvEnumerator.new(true)
      end
    end

    test "#rows yields every record with their cursor position" do
      enum = build_enumerator(open_csv).rows(cursor: 0)
      assert_instance_of(Enumerator::Lazy, enum)

      enum.each_with_index do |element_and_cursor, index|
        assert_equal [csv_rows[index], index], [element_and_cursor[0].fields, element_and_cursor[1]]
      end
    end

    test "#rows enumerator can be resumed" do
      enum = build_enumerator(open_csv).rows(cursor: 3)
      assert_instance_of(Enumerator::Lazy, enum)

      enum.each_with_index do |element_and_cursor, index|
        assert_equal [csv_rows[index + 3], index + 3], [element_and_cursor[0].fields, element_and_cursor[1]]
      end
    end

    test "#rows considers cursor: nil as the start" do
      enum = build_enumerator(open_csv).rows(cursor: nil)
      assert_instance_of(Enumerator::Lazy, enum)

      enum.each_with_index do |element_and_cursor, index|
        assert_equal [csv_rows[index], index], [element_and_cursor[0].fields, element_and_cursor[1]]
      end
    end

    test "#rows enumerator returns size excluding headers" do
      enum = build_enumerator(open_csv)
        .rows(cursor: 0)
      assert_equal 11, enum.size
    end

    test "#rows enumerator returns nil count for a CSV object from a String" do
      enum = build_enumerator(CSV.new(File.read(sample_csv_with_headers))).rows(cursor: 0)
      assert_nil enum.size
    end

    test "#rows enumerator returns total size if resumed" do
      enum = build_enumerator(open_csv).rows(cursor: 10)
      assert_equal 11, enum.size
    end

    test "#rows enumerator returns size including headers" do
      enum = build_enumerator(open_csv(headers: false)).rows(cursor: 10)
      assert_equal 12, enum.size
    end

    test "#batches considers cursor: nil as the start" do
      enum = build_enumerator(open_csv).batches(batch_size: 3, cursor: nil)
      assert_instance_of(Enumerator::Lazy, enum)

      expected_values = csv_rows.each_slice(3).to_a
      enum.each_with_index do |element_and_cursor, index|
        assert_equal [expected_values[index], index], [element_and_cursor[0].map(&:fields), element_and_cursor[1]]
      end
    end

    test "#batches yields every batch with their cursor position" do
      enum = build_enumerator(open_csv).batches(batch_size: 3, cursor: 0)
      assert_instance_of(Enumerator::Lazy, enum)

      expected_values = csv_rows.each_slice(3).to_a
      enum.each_with_index do |element_and_cursor, index|
        assert_equal [expected_values[index], index], [element_and_cursor[0].map(&:fields), element_and_cursor[1]]
      end
    end

    test "#batches enumerator can be resumed from cursor: 2" do
      enum = build_enumerator(open_csv).batches(batch_size: 3, cursor: 2)
      assert_instance_of(Enumerator::Lazy, enum)

      expected_values = csv_rows.each_slice(3).drop(2).to_a
      enum.each_with_index do |element_and_cursor, index|
        assert_equal [expected_values[index], index + 2], [element_and_cursor[0].map(&:fields), element_and_cursor[1]]
      end
    end

    test "#batches enumerator can be resumed from the last uneven batch" do
      enum = build_enumerator(open_csv).batches(batch_size: 2, cursor: 5)
      assert_instance_of(Enumerator::Lazy, enum)

      element_and_cursor = enum.next
      assert_equal [[[11, 111, "Peach"]], 5], [element_and_cursor[0].map(&:fields), element_and_cursor[1]]
      assert_raises(StopIteration) { enum.next }
    end

    test "#batches enumerator returns size" do
      enum = build_enumerator(open_csv)
        .batches(batch_size: 2, cursor: 0)
      assert_equal 6, enum.size

      enum = build_enumerator(open_csv)
        .batches(batch_size: 3, cursor: 0)
      assert_equal 4, enum.size
    end

    test "#batches enumerator returns total size if resumed" do
      enum = build_enumerator(open_csv).batches(batch_size: 2, cursor: 5)
      assert_equal 6, enum.size
    end

    test "#rows work even if system_line_count returns 0" do
      JobIteration::CsvEnumerator.any_instance.stubs(:system_line_count).returns(0)
      enum = build_enumerator(open_csv).rows(cursor: 0)
      assert_equal 11, enum.size
    end

    test "#batches work even if system_line_count returns 0" do
      JobIteration::CsvEnumerator.any_instance.stubs(:system_line_count).returns(0)
      enum = build_enumerator(open_csv).batches(batch_size: 2, cursor: 5)
      assert_equal 6, enum.size
    end

    private

    def build_enumerator(csv)
      JobIteration::CsvEnumerator.new(csv)
    end

    def csv_rows
      @csv_rows ||= open_csv.map(&:fields)
    end

    def sample_csv_with_headers
      ["test", "support", "sample_csv_with_headers.csv"].join("/")
    end

    def open_csv(options = {})
      CSV.open(sample_csv_with_headers, { converters: :integer, headers: true }.merge(options))
    end
  end
end
