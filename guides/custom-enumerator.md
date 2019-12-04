Iteration leverages the [Enumerator](http://ruby-doc.org/core-2.5.1/Enumerator.html) pattern from the Ruby standard library, which allows us to use almost any resource as a collection to iterate.

Consider a custom Enumerator that takes items from a Redis list. Because a Redis List is essentially a queue, we can ignore the cursor:

```ruby
class ListJob < ActiveJob::Base
  include JobIteration::Iteration

  def build_enumerator(*)
    @redis = Redis.new
    Enumerator.new do |yielder|
      yielder.yield @redis.lpop(key), nil
    end
  end

  def each_iteration(item_from_redis)
    # ...
  end
end
```

But what about iterating based on a cursor? Consider this Enumerator that wraps third party API (Stripe) for paginated iteration:

```ruby
class StripeListEnumerator
  # @param resource [Stripe::APIResource] The type of Stripe object to request
  # @param params [Hash] Query parameters for the request
  # @param options [Hash] Request options, such as API key or version
  # @param cursor [String]
  def initialize(resource, params: {}, options: {}, cursor:)
    pagination_params = {}
    pagination_params[:starting_after] = cursor unless cursor.nil?

    @list = resource.public_send(:list, params.merge(pagination_params), options)
      .auto_paging_each.lazy
  end

  def to_enumerator
    to_enum(:each).lazy
  end

  private

  # We yield our enumerator with the object id as the index so it is persisted
  # as the cursor on the job. This allows us to properly set the
  # `starting_after` parameter for the API request when resuming.
  def each
    @list.each do |item, _index|
      yield item, item.id
    end
  end
end
```

```ruby
class StripeJob < ActiveJob::Base
  include JobIteration::Iteration

  def build_enumerator(params, cursor:)
    StripeListEnumerator.new(
      Stripe::Refund,
      params: { charge: "ch_123" },
      options: { api_key: "sk_test_123", stripe_version: "2018-01-18" },
      cursor: cursor
    ).to_enumerator
  end

  def each_iteration(stripe_refund, _params)
    # ...
  end
end
```

We recommend that you read the implementation of the other enumerators that come with the library (`CsvEnumerator`, `ActiveRecordEnumerator`) to gain a better understanding of building Enumerator objects.
