# frozen_string_literal: true

module JobIteration
  # @private
  class NestedEnumerator
    def initialize(enums, cursor: nil)
      unless enums.all?(Proc)
        raise ArgumentError, "enums must contain only procs/lambdas"
      end

      if cursor && enums.size != cursor.size
        raise ArgumentError, "cursor should have one object per enum"
      end

      @enums = enums
      @cursors = cursor || Array.new(enums.size)
    end

    def each(&block)
      return to_enum unless block_given?

      iterate([], 0, &block)
    end

    private

    def iterate(current_objects, index, &block)
      enumerator = @enums[index].call(*current_objects, @cursors[index])

      enumerator.each do |object_from_enumerator, cursor_from_enumerator|
        if index == @cursors.size - 1
          # we've reached the innermost enumerator, yield for `iterate_with_enumerator`
          yield object_from_enumerator, @cursors
        else
          # we need to go deeper
          next_index = index + 1
          iterate(current_objects + [object_from_enumerator], next_index, &block)
          # reset cursor at the index of the nested enumerator that just finished, so we don't skip items when that
          # index is reused in the next nested iteration
          @cursors[next_index] = nil
        end
        @cursors[index] = cursor_from_enumerator
      end
    end
  end
end
