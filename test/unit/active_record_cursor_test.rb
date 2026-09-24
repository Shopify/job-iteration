# frozen_string_literal: true

require "test_helper"

module JobIteration
  class ActiveRecordCursorTest < IterationUnitTest
    test "#next_batch preloads the following batch asynchronously" do
      skip("Only supported on Rails >= 7") unless Product.connection.try(:async_enabled?)

      cursor = ActiveRecordCursor.new(Product.all)
      cursor.next_batch(2)

      assert_predicate(cursor.next_relation, :scheduled?)
    end
  end
end
