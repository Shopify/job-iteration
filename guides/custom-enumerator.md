# Custom Enumerator

Iteration leverages the [Enumerator](http://ruby-doc.org/core-2.5.1/Enumerator.html) pattern from the Ruby standard library, which allows us to use almost any resource as a collection to iterate.

## Cursorless Enumerator

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

## Enumerator with cursor

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

## Notes

We recommend that you read the implementation of the other enumerators that come with the library (`CsvEnumerator`, `ActiveRecordEnumerator`) to gain a better understanding of building Enumerator objects.

### Post-`yield` code

Code that is written after the `yield` in a custom enumerator is not guaranteed to execute. In the case that a job is forced to exit ie `job_should_exit?` is true, then the job is re-enqueued during the yield and the rest of the code in the enumerator does not run. You can follow that logic [here](https://github.com/Shopify/job-iteration/blob/9641f455b9126efff2214692c0bef423e0d12c39/lib/job-iteration/iteration.rb#L128-L131).

### Cursor types

To ensure cursors are not corrupted, they should only be composed of classes Ruby's JSON library can safely serialize and de-serialize. These are:

- `Array`
- `Hash`
- `String`
- `Integer`
- `Float`
- `TrueClass` (`true`)
- `FalseClass` (`false`)
- `NilClass` (`nil`)

For example, if a `Time` object is given as a cursor (perhaps we are iterating over API resources by creation time), it will be serialized by the job adapter, which typically calls `to_s`, meaning upon resumption the job will unexpectedly get receive a String as cursor instead of the original `Time` object.

```ruby
require "time"
class APIJob < ActiveJob::Base
  include JobIteration::Iteration

  def build_enumerator(cursor:)
    Enumerator.new do |yielder|
      build_stream(cursor).each do |item|
        yielder.yield item, item.created_at
      end
    end
  end

  def each_iteration(item_from_api)
    # ...
  end

  private

  def build_stream(cursor)
    return SomeAPI.stream if cursor.nil?

    SomeAPI.stream(since: cursor) # 💥 ArgumentError from API
  end
end
```

Instead, the job should take steps to serialize and deserialize the cursor as an object of a safe class (e.g. `String`):

```diff
   def build_enumerator(cursor:)
     Enumerator.new do |yielder|
       build_stream(cursor).each do |item|
-        yielder.yield item, item.created_at
+        yielder.yield item, item.created_at.iso8601(6)
       end
     end
   end
```

```diff
   def build_stream(cursor)
     return SomeAPI.stream if cursor.nil?

-    SomeAPI.stream(since: cursor) # 💥 ArgumentError from API
+    SomeAPI.stream(since: Time.iso8601(cursor))
   end
```

Use of unsupported classes is deprecated, and will raise an error in a future version of Job Iteration.
