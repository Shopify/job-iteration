# frozen_string_literal: true

require_relative 'deferred_csv_enumerator'

module JobIteration
  # CsvEnumerator makes it possible to write an Iteration job
  # that uses CSV file as a collection to Iterate.
  # @example
  #   def build_enumerator(cursor:)
  #     csv = CSV.open('tmp/files', { converters: :integer, headers: true })
  #     JobIteration::CsvEnumerator.new(csv).rows(cursor: cursor)
  #   end
  #
  #   def each_iteration(row)
  #     ...
  #   end
  class CsvEnumerator
    # Constructs CsvEnumerator instance based on a CSV file.
    # @param [CSV] csv An instance of CSV object
    # @return [JobIteration::CsvEnumerator]
    # @example
    #   csv = CSV.open('tmp/files', { converters: :integer, headers: true })
    #   JobIteration::CsvEnumerator.new(csv).rows(cursor: cursor)
    def initialize(csv)
      @deferred_enumerator = DeferredCsvEnumerator.new(csv)
    end

    # Constructs a enumerator on CSV rows
    # @return [Enumerator] Enumerator instance
    def rows(cursor:)
      deferred_enumerator.rows.call(cursor: cursor)
    end

    # Constructs a enumerator on batches of CSV rows
    # @return [Enumerator] Enumerator instance
    def batches(batch_size:, cursor:)
      deferred_enumerator.batches(batch_size: batch_size).call(cursor: cursor)
    end

    private

    attr_reader :deferred_enumerator
  end
end
