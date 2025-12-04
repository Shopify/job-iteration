# frozen_string_literal: true

require "test_helper"

module JobIteration
  class ActiveRecordEnumeratorTest < IterationUnitTest
    SQL_TIME_FORMAT = "%Y-%m-%d %H:%M:%S.%N"
    test "#records yields every record with their cursor position" do
      enum = build_enumerator.records
      shop_id_tuples = Product.all.order(:id).take(3).map { |shop| [shop, shop.id] }
      assert_equal Product.all.count, enum.size
      enum.first(3).each_with_index do |shop_id, index|
        assert_equal shop_id_tuples[index], shop_id
      end
    end

    test "#records doesn't yield anything if the relation is empty" do
      enum = build_enumerator(relation: Product.none).records

      assert_equal([], enum.to_a)
      assert_equal 0, enum.size
    end

    test "#batches yeilds batches of records with the last record's cursor position" do
      enum = build_enumerator.batches
      shop_id_tuples =
        Product.order(:id).take(4).in_groups_of(2).map { |shops| [shops, shops.last.id] }

      enum.first(2).each_with_index do |shop_id, index|
        assert_equal shop_id_tuples[index], shop_id
      end
    end

    test "#batches doesn't yield anything if the relation is empty" do
      enum = build_enumerator(relation: Product.none).batches

      assert_equal([], enum.to_a)
    end

    test "#batches continues iterating until ActiveRecordCursor returns nil" do
      shops = [Product.first, Product.last]
      JobIteration::ActiveRecordCursor
        .any_instance
        .stubs(:next_batch)
        .returns([shops[0]], [], [shops[1]], nil)

      enum = build_enumerator.batches
      enum.each_with_index do |batch, index|
        assert_equal [[shops[index]], shops[index].id], batch
      end
    end

    test "batch size is configurable" do
      enum = build_enumerator(batch_size: 4).batches
      shops = Product.order(:id).take(4)

      assert_equal([shops, shops.last.id], enum.first)
    end

    class StubbedCursor
      include ActiveSupport::Testing::TimeHelpers
      def initialize(wait_time:)
        @wait_time = wait_time
      end

      def next_batch(*)
        travel(@wait_time)
      end
    end

    test "enumerator next batch is instrumented with proper duration" do
      wait_time = 15.seconds
      freeze_time do
        stubbed_cursor = StubbedCursor.new(wait_time: wait_time)

        ActiveSupport::Notifications.subscribe("active_record_cursor.iteration") do |*args|
          ActiveSupport::Notifications.unsubscribe("active_record_cursor.iteration")
          event = ActiveSupport::Notifications::Event.new(*args)
          assert_equal(wait_time.in_milliseconds, event.duration)
        end
        enum = build_enumerator
        enum.send(:instrument_next_batch, stubbed_cursor)
      end
    end

    test "enumerator next batch is instrumented" do
      ActiveSupport::Notifications.expects(:instrument).with("active_record_cursor.iteration")
      enum = build_enumerator.batches
      enum.first
    end

    test "columns are configurable" do
      enum = build_enumerator(columns: [:updated_at]).batches
      shops = Product.order(:updated_at).take(2)

      assert_equal([shops, shops.last.updated_at.utc.strftime(SQL_TIME_FORMAT)], enum.first)
    end

    test "columns can be an array" do
      enum = build_enumerator(columns: [:updated_at, :id]).batches
      shops = Product.order(:updated_at, :id).take(2)

      assert_equal([shops, [shops.last.updated_at.utc.strftime(SQL_TIME_FORMAT), shops.last.id]], enum.first)
    end

    test "cursor can be used to resume" do
      shops = Product.order(:id).take(3)

      enum = build_enumerator(cursor: shops.shift.id).batches

      assert_equal([shops, shops.last.id], enum.first)
    end

    test "cursor can be used to resume on multiple columns" do
      enum = build_enumerator(columns: [:created_at, :id]).batches
      shops = Product.order(:created_at, :id).take(2)

      cursor = [shops.last.created_at.utc.strftime(SQL_TIME_FORMAT), shops.last.id]
      assert_equal([shops, cursor], enum.first)

      enum = build_enumerator(columns: [:created_at, :id], cursor: cursor).batches
      shops = Product.order(:created_at, :id).offset(2).take(2)

      cursor = [shops.last.created_at.utc.strftime(SQL_TIME_FORMAT), shops.last.id]
      assert_equal([shops, cursor], enum.first)
    end

    test "using custom timezone results in a cursor with the correct offset" do
      custom_timezone = "Eastern Time (US & Canada)"
      enum = build_enumerator(columns: [:created_at, :id], timezone: custom_timezone).batches
      shops = Product.order(:created_at, :id).take(2)

      cursor = [shops.last.created_at.in_time_zone(custom_timezone).strftime(SQL_TIME_FORMAT), shops.last.id]
      assert_equal([shops, cursor], enum.first)
    end

    test "columns with date type are serialized to ISO8601 format" do
      Event.create!(name: "Conference", occurred_on: Date.new(2025, 10, 15))
      Event.create!(name: "Workshop", occurred_on: Date.new(2025, 10, 20))

      enum = build_enumerator(relation: Event.all, columns: [:occurred_on]).batches
      events = Event.order(:occurred_on).take(2)

      assert_equal([events, "2025-10-20"], enum.first)
    end

    test "cursor can be used to resume on date column" do
      Event.create!(name: "Event 1", occurred_on: Date.new(2025, 1, 10))
      Event.create!(name: "Event 2", occurred_on: Date.new(2025, 1, 20))
      Event.create!(name: "Event 3", occurred_on: Date.new(2025, 1, 30))

      enum = build_enumerator(relation: Event.all, columns: [:occurred_on, :id], cursor: ["2025-01-10", Event.first.id]).batches
      events = Event.order(:occurred_on, :id).offset(1).take(2)

      cursor = [events.last.occurred_on.iso8601, events.last.id]
      assert_equal([events, cursor], enum.first)
    end

    test "#size returns the number of items in the relation" do
      enum = build_enumerator(relation: Product.all)

      assert_equal(10, enum.size)
    end

    test "#size returns the number of items in a relation with a subset of columns" do
      enum = build_enumerator(relation: Product.select(:id, :name), columns: [:id, :name])

      assert_equal(10, enum.size)
    end

    if ActiveRecord.version >= Gem::Version.new("7.1.0.alpha")
      test "enumerator for a relation with a composite primary key" do
        TravelRoute.create!(origin: "A", destination: "B")
        TravelRoute.create!(origin: "A", destination: "C")
        TravelRoute.create!(origin: "B", destination: "A")

        enum = build_enumerator(relation: TravelRoute.all, batch_size: 2)

        cursors = []
        enum.records.each { |_record, cursor| cursors << cursor }

        assert_equal([["A", "B"], ["A", "C"], ["B", "A"]], cursors)
      end

      test "enumerator for a relation with a composite primary key using :id" do
        Order.create!(name: "Yellow socks", shop_id: 3)
        Order.create!(name: "Red hat", shop_id: 1)
        Order.create!(name: "Blue jeans", shop_id: 1)

        enum = build_enumerator(relation: Order.all, batch_size: 2)

        order_names = []
        enum.records.each { |record, _cursor| order_names << record.name }

        assert_equal(["Red hat", "Blue jeans", "Yellow socks"], order_names)
      end
    end

    private

    def build_enumerator(relation: Product.all, batch_size: 2, timezone: nil, columns: nil, cursor: nil)
      JobIteration::ActiveRecordEnumerator.new(
        relation,
        batch_size: batch_size,
        timezone: timezone,
        columns: columns,
        cursor: cursor,
      )
    end
  end
end
