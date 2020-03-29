# frozen_string_literal: true

require "test_helper"

module JobIteration
  class ActiveRecordEnumeratorTest < IterationUnitTest
    test "omg" do
      result = parse(Product.where('created_at <= ?', 48.hours.ago))
      assert_kind_of QueryParser::ResultWithColumns, result
      assert_equal ["created_at"], result.columns

      result = parse(Product.where("products.created_at <= ?", 2.days.ago))
      assert_kind_of QueryParser::ResultWithColumns, result
      assert_equal ["products.created_at"], result.columns

      result = parse(Product.where('created_at <= ? AND 1=1', 48.hours.ago))
      assert_kind_of QueryParser::ResultWithColumns, result
      assert_equal ["created_at", "1"], result.columns

      result = parse(Product.where('created_at <= ? AND shop_id IN(?)', 48.hours.ago, [123,456]))
      assert_kind_of QueryParser::ResultWithColumns, result

      result = parse(Product.where(state: :requested).where("created_at <= ? OR test = 1", Time.at(1585512223)))
      assert_kind_of QueryParser::ResultWithViolations, result
      assert_equal ["OR is not allowed: \"created_at <= '2020-03-29 20:03:43' OR test = 1\""], result.violations

      result = parse(Product.where.not(shop_id: nil))
      assert_kind_of QueryParser::ResultWithViolations, result
      assert_equal ["NOT is not allowed: shop_id"], result.violations

      result = parse(Product.where(state: :requested).where("created_at <= ? AND test = 1", Time.now.utc))
      assert_kind_of QueryParser::ResultWithColumns, result
      assert_equal ["state", "created_at", "test"], result.columns

      result = parse(Product.where(state: nil).where("updated_at <= ?", 2.days.ago))
      assert_kind_of QueryParser::ResultWithColumns, result
      assert_equal ["state", "updated_at"], result.columns

      result = parse(Product.where(state: :requested))
      assert_kind_of QueryParser::ResultWithColumns, result
      assert_equal ["state"], result.columns
      result = parse(Product.where(shop_id: [1,2,3]))
      assert_kind_of QueryParser::ResultWithColumns, result
      assert_equal ["shop_id"], result.columns

      result = parse(Product.where(shop_id: nil))
      assert_kind_of QueryParser::ResultWithColumns, result
      assert_equal ["shop_id"], result.columns

      result = parse(Product.where("shop_id IS NOT ?", 1))
      assert_kind_of QueryParser::ResultWithColumns, result
      assert_equal ["shop_id"], result.columns

      result = parse(Product.where("shop_id IS NOT NULL"))
      assert_kind_of QueryParser::ResultWithColumns, result
      assert_equal ["shop_id"], result.columns

      result = parse(Product.where("shop_id IS NULL"))
      assert_kind_of QueryParser::ResultWithColumns, result
      assert_equal ["shop_id"], result.columns
    end

    def parse(relation)
      QueryParser::Parser.parse(relation)
    end
  end
end
