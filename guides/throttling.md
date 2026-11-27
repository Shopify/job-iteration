Iteration comes with a special wrapper enumerator that allows you to throttle iterations based on external signal (e.g. database health).

Consider this example:

```ruby
class InactiveAccountDeleteJob < ActiveJob::Base
  include JobIteration::Iteration

  def build_enumerator(_params, cursor:)
    enumerator_builder.active_record_on_batches(
      Account.inactive,
      cursor: cursor
    )
  end

  def each_iteration(batch, _params)
    Account.where(id: batch.map(&:id)).delete_all
  end
end
```

For an app that keeps track of customer accounts, it's typical to purge old data that's no longer relevant for storage.

At the same time, if you've got a lot of DB writes to perform, this can cause extra load on the database and slow down other parts of your service.

You can change `build_enumerator` to wrap enumeration on DB rows into a throttle enumerator, which takes signal as a proc and enqueues the job for later in case the proc returned `true`.

```ruby
def build_enumerator(_params, cursor:)
  enumerator_builder.build_throttle_enumerator(
    enumerator_builder.active_record_on_batches(
      Account.inactive,
      cursor: cursor
    ),
    throttle_on: -> { DatabaseStatus.unhealthy? },
    backoff: 30.seconds
  )
end
```

## Checking the throttle before fetching the next value

By default, the throttle enumerator calls `throttle_on` after the wrapped enumerator has produced the next value and
before your job processes it. For the Active Record enumerators, that means the page query has already run: when the
throttle fires, the job discards the page it just loaded and loads it again when it resumes. A job throttled on
database health therefore keeps sending the database it is protecting one query per backoff interval, for as long as
the database stays unhealthy.

Pass `check_before_fetch: true` to check the throttle before the wrapped enumerator is asked for the next value
instead:

```ruby
def build_enumerator(_params, cursor:)
  enumerator_builder.build_throttle_enumerator(
    enumerator_builder.active_record_on_batches(
      Account.inactive,
      cursor: cursor
    ),
    throttle_on: -> { DatabaseStatus.unhealthy? },
    backoff: 30.seconds,
    check_before_fetch: true,
  )
end
```

`throttle_on` is then called once before iteration starts and again after each value has been processed. Things to
know before you turn it on:

* **`throttle_on` is called one extra time per job run.** A run that processes N values calls it N + 1 times instead
  of N, and the extra call comes before the first value. Throttles that count calls (for example, "throttle after
  every 100 batches") see that extra call.
* **The check after the last value can fire.** The job is then re-enqueued even though there was nothing left to
  process, and its next run makes one query that finds no rows before the job completes. That is cheaper than a page
  that is loaded and discarded.
* **It only removes the waste at boundaries between values.** `active_record_on_records` loads a page of records and
  yields them one at a time, so if the throttle fires in the middle of a page, the rest of that page is still
  discarded and loaded again on resume. `active_record_on_batches` and `active_record_on_batch_relations` yield a whole
  page at a time, so nothing is discarded.
* **Stacked throttles are checked in a different order.** When one throttle enumerator wraps another and both use
  `check_before_fetch: true`, the outer throttle is checked first, then the inner one, both before the fetch. With the
  default, the order is: fetch, inner throttle, outer throttle. A throttle that does not opt in still runs after the
  fetch, so turn the option on for every throttle in the stack.
* **Nested enumerators** (`enumerator_builder.nested`) are checked after each innermost value, before any level fetches
  again, including when moving on to the next parent record.

The option defaults to `false`, which keeps the existing behaviour.

If you want to apply throttling on all jobs, you can subclass your own EnumeratorBuilder and override the default
enumerator builder. The builder always wraps the returned enumerators from `build_enumerator`

```ruby
class MyOwnBuilder < JobIteration::EnumeratorBuilder
  class Wrapper < Enumerator
    class << self
      def wrap(_builder, enum)
        ThrottleEnumerator.new(
          enum,
          nil,
          throttle_on: -> { DatabaseStatus.unhealthy? },
          backoff: 30.seconds
        )
      end
    end
  end
end

JobIteration.enumerator_builder = MyOwnBuilder
```

Note that it's up to you to implement `DatabaseStatus.unhealthy?` that works for your database choice. At Shopify, a helper like `DatabaseStatus` checks the following MySQL metrics:

* Replication lag across all regions
* DB threads
* DB is available for writes (otherwise indicates a failover happening)
* [Semian](https://github.com/shopify/semian) open circuits
