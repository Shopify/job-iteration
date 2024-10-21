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
