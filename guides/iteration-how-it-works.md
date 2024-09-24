# Iteration: how it works

The main idea behind Iteration is to provide an API to describe jobs in an interruptible manner, in contrast with implementing one massive `#perform` method that is impossible to interrupt safely.

Exposing the enumerator and the action to apply allows us to keep a cursor and interrupt between iterations. Let's see what this looks like with an  ActiveRecord relation (and Enumerator).

1. `build_enumerator` is called, which constructs `ActiveRecordEnumerator` from an ActiveRecord relation (`Product.all`)
2. The first batch of records is loaded:

```sql
SELECT  `products`.* FROM `products` ORDER BY products.id LIMIT 100
```

3. The job iterates over two records of the relation and then receives `SIGTERM` (graceful termination signal) caused by a deploy.
4. The signal handler sets a flag that makes `job_should_exit?` return `true`.
5. After the last iteration is completed, we will check `job_should_exit?` which now returns `true`.
6. The job stops iterating and pushes itself back to the queue, with the latest `cursor_position` value.
7. Next time when the job is taken from the queue, we'll load records starting from the last primary key that was processed:

```sql
SELECT  `products`.* FROM `products` WHERE (products.id > 2) ORDER BY products.id LIMIT 100
```

## Exceptions inside `each_iteration`

Unrescued exceptions inside the `each_iteration` block are handled the same way as exceptions occuring in `perform` for a regular Active Job subclass, meaning you need to configure it to retry using [`retry_on`](https://api.rubyonrails.org/classes/ActiveJob/Exceptions/ClassMethods.html#method-i-retry_on) or manually call [`retry_job`](https://api.rubyonrails.org/classes/ActiveJob/Exceptions.html#method-i-retry_job). The job will re-enqueue itself with the last successful cursor, the iteration that failed will be retried with the same parameters and the cursor will only move if that iteration succeeds. This behaviour may be enough for intermittent errors, such as network connection failures, but if your execution is deterministic and you have an error, subsequent iterations will never run.

In other words, if you are trying to process 100 records but the job consistently fails on the 61st, only the first 60 will be processed and the job will try to process the 61st record until retries are exhausted.

If no retries are configured or retries are exhausted, Active Job 'bubbles up' the exception to the job backend. Retries by the backend (e.g. Sidekiq) are not supported, meaning that jobs retried by the job backend instead of Active Job will restart from the beginning.

## Stopping a job

Because jobs typically retry when exceptions are thrown, there is a special mechanism to fully stop a job that still has iterations remaining. To do this, you can `throw(:abort)`. This is then caught by job-iteration and signals that the job should complete now, regardless of its iteration state.

## Signals

It's critical to know [UNIX signals](https://www.tutorialspoint.com/unix/unix-signals-traps.htm) in order to understand how interruption works. There are two main signals that Sidekiq and Resque use: `SIGTERM` and `SIGKILL`. `SIGTERM` is the graceful termination signal which means that the process should exit _soon_, not immediately. For Iteration, it means that we have time to wait for the last iteration to finish and to push job back to the queue with the last cursor position.
`SIGTERM` is what allows Iteration to work. In contrast, `SIGKILL` means immediate exit. It doesn't let the worker terminate gracefully, instead it will drop the job and exit as soon as possible.

Most of the deploy strategies (Kubernetes, Heroku, Capistrano) send `SIGTERM` before shutting down a node, then wait for a timeout (usually from 30 seconds to a minute) to send `SIGKILL` if the process has not terminated yet.

Further reading: [Sidekiq signals](https://github.com/mperham/sidekiq/wiki/Signals).

## Enumerators

In the early versions of Iteration, `build_enumerator` used to return ActiveRecord relations directly, and we would infer the Enumerator based on the type of object. We used to support ActiveRecord relations, arrays and CSVs. This made it hard to add support for other types of enumerations, and it was easy for developers to make mistakes and return an array of ActiveRecord objects, and for us starting to treat that as an array instead of as an ActiveRecord relation.

The current version of Iteration supports _any_ Enumerator. We expose helpers to build common enumerators conveniently (`enumerator_builder.active_record_on_records`), but it's up to a developer to implement [a custom Enumerator](custom-enumerator.md).

Further reading: [ruby-doc](https://ruby-doc.org/3.2.1/Enumerator.html), [a great post about Enumerators](http://blog.arkency.com/2014/01/ruby-to-enum-for-enumerator/).
