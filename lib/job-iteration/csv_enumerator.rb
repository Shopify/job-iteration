# frozen_string_literal: true

module JobIteration
  class CsvEnumerator
    def initialize(csv)
      unless csv.instance_of?(CSV)
        raise ArgumentError, "CsvEnumerator.new takes CSV object"
      end

      @csv = csv
    end

    def rows(cursor:)
      @csv.lazy
        .each_with_index
        .drop(cursor.to_i)
        .to_enum { count_rows_in_file }
    end

    def batches(batch_size:, cursor:)
      @csv.lazy
        .each_slice(batch_size)
        .each_with_index
        .drop(cursor.to_i)
        .to_enum { (count_rows_in_file.to_f / batch_size).ceil }
    end

    private

    def count_rows_in_file
      begin
        filepath = @csv.path
      rescue NoMethodError
        return
      end

      count = `wc -l < #{filepath}`.strip.to_i
      count -= 1 if @csv.headers
      count
    end
  end
end
