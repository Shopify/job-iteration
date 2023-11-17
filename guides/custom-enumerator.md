# Custom Enumerator

`Iteration` leverages the [Enumerator](https://ruby-doc.org/3.2.1/Enumerator.html) pattern from the Ruby standard library,
which allows us to use almost any resource as a collection to iterate.

Before writing an enumerator, it is important to understand [how Iteration works](iteration-how-it-works.md) and how
your enumerator will be used by it. An enumerator must `yield` two things in the following order as positional
arguments:
- An object to be processed in a job `each_iteration` method
- A cursor position, which `Iteration` will persist if `each_iteration` returns successfully and the job is forced to shut
  down. It can be any data type your job backend can serialize and deserialize correctly.

A job that includes `Iteration` is first started with `nil` as the cursor. When resuming an interrupted job, `Iteration`
will deserialize the persisted cursor and pass it to the job's `build_enumerator` method, which your enumerator uses to
find objects that come _after_ the last successfully processed object. The [array enumerator](https://github.com/Shopify/job-iteration/blob/v1.3.6/lib/job-iteration/enumerator_builder.rb#L50-L67)
is a simple example which uses the array index as the cursor position.

In addition to the remainder of this guide, we recommend you read the implementation of the other enumerators that come with the library (`CsvEnumerator`, `ActiveRecordEnumerator`) to gain a better understanding of building enumerators.

## Enumerator with cursor

For a more complex example, consider this `Enumerator` that wraps a third party API (Stripe) for paginated iteration and
stores a string as the cursor position:

```ruby
class StripeListEnumerator
  # @see https://stripe.com/docs/api/pagination
  # @param resource [Stripe::APIResource] The type of Stripe object to request
  # @param params [Hash] Query parameters for the request
  # @param options [Hash] Request options, such as API key or version
  # @param cursor [nil, String] The Stripe ID of the last item iterated over
  def initialize(resource, params: {}, options: {}, cursor:)
    pagination_params = {}
    pagination_params[:starting_after] = cursor unless cursor.nil?

    # The following line makes a request, consider adding your rate limiter here.
    @list = resource.public_send(:list, params.merge(pagination_params), options)
  end

  def to_enumerator
    to_enum(:each).lazy
  end

  private

  # We yield our enumerator with the object id as the index so it is persisted
  # as the cursor on the job. This allows us to properly set the
  # `starting_after` parameter for the API request when resuming.
  def each
    loop do
      @list.each do |item, _index|
        # The first argument is what gets passed to `each_iteration`.
        # The second argument (item.id) is going to be persisted as the cursor,
        # it doesn't get passed to `each_iteration`.
        yield item, item.id
      end

      # The following line makes a request, consider adding your rate limiter here.
      @list = @list.next_page

      break if @list.empty?
    end
  end
end
```

### Usage

Here we leverage the Stripe cursor pagination where the cursor is an ID of a specific item in the collection. The job
which uses such an `Enumerator` would then look like so:

```ruby
class LoadRefundsForChargeJob < ActiveJob::Base
  include JobIteration::Iteration

  # If you added your own rate limiting above, handle it here. For example:
  # retry_on(MyRateLimiter::LimitExceededError, wait: 30.seconds, attempts: :unlimited)
  # Use an exponential back-off strategy when Stripe's API returns errors.

  def build_enumerator(charge_id, cursor:)
    StripeListEnumerator.new(
      Stripe::Refund,
      params: { charge: charge_id}, # "charge_id" will be a prefixed Stripe ID such as "chrg_123"
      options: { api_key: "sk_test_123", stripe_version: "2018-01-18" },
      cursor: cursor
    ).to_enumerator
  end

  # Note that in this case `each_iteration` will only receive one positional argument per iteration.
  # If what your enumerator yields is a composite object you will need to unpack it yourself
  # inside the `each_iteration`.
  def each_iteration(stripe_refund, charge_id)
    # ...
  end
end
```

and you initiate the job with

```ruby
LoadRefundsForChargeJob.perform_later(charge_id = "chrg_345")
```

### Cursor Serialization

Cursors should be of a [type that Active Job can serialize](https://guides.rubyonrails.org/active_job_basics.html#supported-types-for-arguments).

For example, consider:

```ruby
FancyCursor = Struct.new(:wrapped_value) do
  def to_s
    wrapped_value
  end
end
```

```ruby
def build_enumerator(cursor:)
  Enumerator.new do |yielder|
    # ...something with fancy cursor...
    yielder.yield 123, FancyCursor.new(:abc)
  end
end
```

If this job was interrupted, Active Job would be unable to serialize
`FancyCursor`, and Job Iteration would fallback to the legacy behavior of not
serializing the cursor. This would typically result in the queue adapter
eventually serializing the cursor as JSON by calling `.to_s` on it. The cursor
would be deserialized as `:abc`, rather than the intended `FancyCursor.new(:abc)`.

To avoid this, job authors should take care to ensure that their cursor is
serializable by Active Job. This can be done in a couple ways, such as:
- [adding `GlobalID` support to the cursor class](https://guides.rubyonrails.org/active_job_basics.html#globalid)
- [implementing a custom Active Job argument serializer for the cursor class](https://guides.rubyonrails.org/active_job_basics.html#serializers)
- handling (de)serialization in the job/enumerator itself
    ```ruby
     def build_enumerator(cursor:)
       fancy_cursor = FancyCursor.new(cursor) unless cursor.nil?
       Enumerator.new do |yielder|
         # ...something with fancy cursor...
         yielder.yield 123, FancyCursor(:abc).wrapped_value
       end
     end
    ```
Note that starting in 2.0, Job Iteration will stop supporting fallback behavior
and raise when it encounters an unserializable cursor. To opt-in to this behavior early, set
```ruby
JobIteration.enforce_serializable_cursors = true
```
or, to support gradual migration, a per-class option is also available to override the global value, if set:
```ruby
class MyJob < ActiveJob::Base
  include JobIteration::Iteration
  self.job_iteration_enforce_serializable_cursors = true
```


## Cursorless enumerator

Sometimes you can ignore the cursor. Consider the following custom `Enumerator` that takes items from a Redis list, which
is essentially a queue. Even if this job doesn't need to persist a cursor in order to resume, it can still use
`Iteration`'s signal handling to finish `each_iteration` and gracefully terminate.

```ruby
class RedisPopListJob < ActiveJob::Base
  include JobIteration::Iteration

  # @see https://redis.io/commands/lpop/
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

## Caveats

### Post-`yield` code

Code that is written after the `yield` in a custom enumerator is not guaranteed to execute. In the case that a job is
forced to exit ie `job_should_exit?` is true, then the job is re-enqueued during the yield and the rest of the code in
the enumerator does not run. You can follow that logic
[here](https://github.com/Shopify/job-iteration/blob/v1.3.6/lib/job-iteration/iteration.rb#L161-L165) and
[here](https://github.com/Shopify/job-iteration/blob/v1.3.6/lib/job-iteration/iteration.rb#L131-L143)
