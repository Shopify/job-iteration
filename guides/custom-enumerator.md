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
  # @param cursor [String] The Stripe ID of the last item iterated over
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
LoadRefundsForChargeJob.perform_later(_charge_id = "chrg_345")
```

We recommend that you read the implementation of the other enumerators that come with the library (`CsvEnumerator`, `ActiveRecordEnumerator`) to gain a better understanding of building Enumerator objects.

Code that is written after the `yield` in a custom enumerator is not guaranteed to execute. In the case that a job is forced to exit ie `job_should_exit?` is true, then the job is re-enqueued during the yield and the rest of the code in the enumerator does not run. You can follow that logic [here](https://github.com/Shopify/job-iteration/blob/9641f455b9126efff2214692c0bef423e0d12c39/lib/job-iteration/iteration.rb#L128-L131).
