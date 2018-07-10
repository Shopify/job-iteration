# Job Iteration API

Meet Iteration, an extension for [ActiveJob](https://github.com/rails/rails/tree/master/activejob) that makes your jobs interruptible and resumable, with saving all progress that the job has made (aka checkpoint for jobs).

## Background

Imagine the following job:

```ruby
class SimpleJob < ActiveJob::Base
  def perform
    User.find_each do |user|
      user.notify_about_something
    end
  end
end
```

The job would run fairly quickly when you only have a hundred User records. But as the number of records grows, it will take longer for a job to iterate over all Users. Eventually, there will be millions of records to iterate and the job will end up taking hours and days.

With frequent deploys and worker restarts, it would mean that a job will be either lost of started from the beginning. Some records (especially those in the beginning of the relation) will be processed more than once.

Cloud environments are also unpredictable, and there's no way to guarantee that a single job will have reserved hardware to run for hours and days. What if AWS diagnosed the instance as unhealthy and will restart it in 5 minutes? What if Kubernetes pod is getting [evicted](https://kubernetes.io/docs/concepts/workloads/pods/disruptions/)? Again, all job progress will be lost.

Software that is designed for high availability [must be friendly](https://12factor.net/disposability) to interruptions that come from the infrastructure. That's exactly what Iteration brings to ActiveJob. It's been developed at Shopify to safely process long-running jobs, in Cloud, and has been working in production since May 2017.

We recommend you to watch a [conference talk](https://www.youtube.com/watch?v=XvnWjsmAl60) about the ideas and history behind Iteration API.

## Getting started

Add this line to your application's Gemfile:

```ruby
gem 'job-iteration'
```

And then execute:

    $ bundle

In the job, include `JobIteration::Iteration` module and start describing the job with two methods (`build_enumerator` and `each_iteration`) instead of `perform`:

```ruby
class NotifyUsersJob < ActiveJob::Base
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
class BatchesJob < ActiveJob::Iteration
  def build_enumerator(product_id, cursor:)
    enumerator_builder.active_record_on_batches(
      Product.find(product_id).comments,
      cursor: cursor,
      batch_size: 100,
    )
  end

  def each_iteration(batch_of_comments, product_id)
    # batch_of_users will contain batches of 100 records
    Comment.where(id: batch_of_comments.map(&:id)).update_all(deleted: true)
  end
end
```

```ruby
class ArrayJob < ActiveJob::Iteration
  def build_enumerator(cursor:)
    enumerator_builder.array(['build', 'enumerator', 'from', 'any', 'array'], cursor: cursor)
  end

  def each_iteration(array_element)
    # use array_element
  end
end
```

```ruby
class CsvJob < ActiveJob::Iteration
  def build_enumerator(import_id, cursor:)
    import = Import.find(import_id)
    JobIteration::CsvEnumerator.new(import.csv).rows(cursor: cursor)
  end

  def each_iteration(csv_row)
    # insert csv_row to database
  end
end
```

## Requirements

ActiveJob is the primary requirement for Iteration. It's not yet compatible with [vanilla](https://github.com/mperham/sidekiq/wiki/Active-Job) Sidekiq API.

### Sidekiq

Unless you are running on Heroku, we recommend you to time Sidekiq's [timeout](https://github.com/mperham/sidekiq/wiki/Deployment#overview) option from the default 8 seconds to 25-30 seconds, to allow the last `each_iteration` to complete and gracefully shutdown.

### Resque

There a few configuration assumptions that are required for Iteration to work with Resque. `GRACEFUL_TERM` must be enabled (giving the job ability to gracefully interrupt), and `FORK_PER_JOB` is recommended to be disabled (set to `false`).

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

After checking out the repo, run `bundle install` to install dependencies. Then, run `bundle exec rake test` to run the tests.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/Shopify/job-iteration. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](http://contributor-covenant.org) code of conduct.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Job::Iteration project’s codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/kirs/job-iteration/blob/master/CODE_OF_CONDUCT.md).
