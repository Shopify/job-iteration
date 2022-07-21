# Job Iteration API

[![CI](https://github.com/Shopify/job-iteration/actions/workflows/ci.yml/badge.svg)](https://github.com/Shopify/job-iteration/actions/workflows/ci.yml)

Meet Iteration, an extension for [ActiveJob](https://github.com/rails/rails/tree/main/activejob) that makes your jobs interruptible and resumable, saving all progress that the job has made (aka checkpoint for jobs).

## Background

Imagine the following job:

```ruby
class SimpleJob < ApplicationJob
  def perform
    User.find_each do |user|
      user.notify_about_something
    end
  end
end
```

The job would run fairly quickly when you only have a hundred `User` records. But as the number of records grows, it will take longer for a job to iterate over all Users. Eventually, there will be millions of records to iterate and the job will end up taking hours or even days.

With frequent deploys and worker restarts, it would mean that a job will be either lost or restarted from the beginning. Some records (especially those in the beginning of the relation) will be processed more than once.

Cloud environments are also unpredictable, and there's no way to guarantee that a single job will have reserved hardware to run for hours and days. What if AWS diagnosed the instance as unhealthy and will restart it in 5 minutes? What if a Kubernetes pod is getting [evicted](https://kubernetes.io/docs/concepts/workloads/pods/disruptions/)? Again, all job progress will be lost. At Shopify, we also use it to interrupt workloads safely when moving tenants between shards and move shards between regions.

Software that is designed for high availability [must be resilient](https://12factor.net/disposability) to interruptions that come from the infrastructure. That's exactly what Iteration brings to ActiveJob. It's been developed at Shopify to safely process long-running jobs, in Cloud, and has been working in production since May 2017.

We recommend that you watch one of our [conference talks](https://www.youtube.com/watch?v=XvnWjsmAl60) about the ideas and history behind Iteration API.

## Getting started

Add this line to your application's Gemfile:

```ruby
gem 'job-iteration'
```

And then execute:

    $ bundle

In the job, include `JobIteration::Iteration` module and start describing the job with two methods (`build_enumerator` and `each_iteration`) instead of `perform`:

```ruby
class NotifyUsersJob < ApplicationJob
  include JobIteration::Iteration

  def build_enumerator(cursor:)
    enumerator_builder.active_record_on_records(
      User.all,
      cursor: cursor,
    )
  end

  def each_iteration(user)
    user.notify_about_something
  end
end
```

`each_iteration` will be called for each `User` model in `User.all` relation. The relation will be ordered by primary key, exactly like `find_each` does.

Check out more examples of Iterations:

```ruby
class BatchesJob < ApplicationJob
  include JobIteration::Iteration

  def build_enumerator(product_id, cursor:)
    enumerator_builder.active_record_on_batches(
      Comment.where(product_id: product_id).select(:id),
      cursor: cursor,
      batch_size: 100,
    )
  end

  def each_iteration(batch_of_comments, product_id)
    comment_ids = batch_of_comments.map(&:id)
    CommentService.call(comment_ids: comment_ids)
  end
end
```

```ruby
class BatchesAsRelationJob < ApplicationJob
  include JobIteration::Iteration

  def build_enumerator(product_id, cursor:)
    enumerator_builder.active_record_on_batch_relations(
      Product.find(product_id).comments,
      cursor: cursor,
      batch_size: 100,
    )
  end

  def each_iteration(batch_of_comments, product_id)
    # batch_of_comments will be a Comment::ActiveRecord_Relation
    batch_of_comments.update_all(deleted: true)
  end
end
```

```ruby
class ArrayJob < ApplicationJob
  include JobIteration::Iteration

  def build_enumerator(cursor:)
    enumerator_builder.array(['build', 'enumerator', 'from', 'any', 'array'], cursor: cursor)
  end

  def each_iteration(array_element)
    # use array_element
  end
end
```

```ruby
class CsvJob < ApplicationJob
  include JobIteration::Iteration

  def build_enumerator(import_id, cursor:)
    import = Import.find(import_id)
    enumerator_builder.csv(import.csv, cursor: cursor)
  end

  def each_iteration(csv_row)
    # insert csv_row to database
  end
end
```

Iteration hooks into Sidekiq and Resque out of the box to support graceful interruption. No extra configuration is required.

## Guides

* [Iteration: how it works](guides/iteration-how-it-works.md)
* [Best practices](guides/best-practices.md)
* [Writing custom enumerator](guides/custom-enumerator.md)
* [Throttling](guides/throttling.md)

For more detailed documentation, see [rubydoc](https://www.rubydoc.info/github/Shopify/job-iteration).

## Requirements

ActiveJob is the primary requirement for Iteration. While there's nothing that prevents it, Iteration is not yet compatible with [vanilla](https://github.com/mperham/sidekiq/wiki/Active-Job) Sidekiq API.

### API

Iteration job must respond to `build_enumerator` and `each_iteration` methods. `build_enumerator` must return [Enumerator](http://ruby-doc.org/core-2.5.1/Enumerator.html) object that respects the `cursor` value.

### Sidekiq adapter

Unless you are running on Heroku, we recommend you to tune Sidekiq's [timeout](https://github.com/mperham/sidekiq/wiki/Deployment#overview) option from the default 8 seconds to 25-30 seconds, to allow the last `each_iteration` to complete and gracefully shutdown.

### Resque adapter

There a few configuration assumptions that are required for Iteration to work with Resque. `GRACEFUL_TERM` must be enabled (giving the job ability to gracefully interrupt), and `FORK_PER_JOB` is recommended to be disabled (set to `false`).

## FAQ

**Why can't I just iterate in `#perform` method and do whatever I want?** You can, but then your job has to comply with a long list of requirements, such as the ones above. This creates leaky abstractions more easily, when instead we can expose a more powerful abstraction for developers--without exposing the underlying infrastructure.

**What happens when my job is interrupted?** A checkpoint will be persisted to Redis after the current `each_iteration`, and the job will be re-enqueued. Once it's popped off the queue, the worker will work off from the next iteration.

**What happens with retries?** An interruption of a job does not count as a retry. The iteration of job that caused the job to fail will be retried and progress will continue from there on.

**What happens if my iteration takes a long time?** We recommend that a single `each_iteration` should take no longer than 30 seconds. In the future, this may raise an exception.

**Why is it important that `each_iteration` takes less than 30 seconds?** When the job worker is scheduled for restart or shutdown, it gets a notice to finish remaining unit of work. To guarantee that no progress is lost we need to make sure that `each_iteration` completes within a reasonable amount of time.

**What do I do if each iteration takes a long time, because it's doing nested operations?** If your `each_iteration` is complex, we recommend enqueuing another job, which will run your nested business logic. We may expose primitives in the future to do this more effectively, but this is not terribly common today.

**Why do I use have to use this ugly helper in `build_enumerator`? Why can't you automatically infer it?** This is how the first version of the API worked. We checked the type of object returned by `build_enumerable`, and whether it was ActiveRecord Relation or an Array, we used the matching adapter. This caused opaque type branching in Iteration internals and it didn’t allow developers to craft their own Enumerators and control the cursor value. We made a decision to _always_ return Enumerator instance from `build_enumerator`. Now we provide explicit helpers to convert ActiveRecord Relation or an Array to Enumerator, and for more complex iteration flows developers can build their own `Enumerator` objects.

**What is the difference between Enumerable and Enumerator?** We recomend [this post](http://blog.arkency.com/2014/01/ruby-to-enum-for-enumerator/) to learn more about Enumerators in Ruby.

**My job has a complex flow. How do I write my own Enumerator?** Iteration API takes care of persisting the cursor (that you may use to calculate an offset) and controlling the job state. The power of Enumerator object is that you can use the cursor in any way you want. One example is a cursorless job that pops records from a datastore until the job is interrupted:

```ruby
class MyJob < ApplicationJob
  include JobIteration::Iteration

  def build_enumerator(cursor:)
    Enumerator.new do
      Redis.lpop("mylist") # or: Kafka.poll(timeout: 10.seconds)
    end
  end

  def each_iteration(element_from_redis)
    # ...
  end
end
```

## Credits

This project would not be possible without these individuals (in alphabetical order):

* Daniella Niyonkuru
* Emil Stolarsky
* Florian Weingarten
* Guillaume Malette
* Hormoz Kheradmand
* Mohamed-Adam Chaieb
* Simon Eskildsen

## Development

After checking out the repo, run `bin/setup` to install dependencies and create mysql database. Then, run `bundle exec rake test` to run the tests.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/Shopify/job-iteration. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](http://contributor-covenant.org) code of conduct.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Job::Iteration project’s codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/Shopify/job-iteration/blob/main/CODE_OF_CONDUCT.md).
