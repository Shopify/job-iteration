### Main (unreleased)
Nil

## v1.5.0 (May 29, 2024)
### Changes

- [437](https://github.com/Shopify/job-iteration/pull/437) - Use minimum between per-class `job_iteration_max_job_runtime` and `JobIteration.max_job_runtime`, instead of enforcing only setting decreasing values.
  Because it is possible to change the global or parent values after setting the value on a class, it is not possible to truly enforce the decreasing value constraint. Instead, we now use the minimum between the global value and per-class value. This is considered a non-breaking change, as it should not break any **existing** code, it only removes the constraint on new classes.
- [443](https://github.com/Shopify/job-iteration/pull/443) - Use Sidekiq `:quit` callback to detect graceful shutdown. This makes job-iteration compatible with Sidekiq run in embedded mode.
- [445](https://github.com/Shopify/job-iteration/pull/445) - Add the `around_iterate` callback, which runs around each call of `each_iteration`. This adds extensibility to build some generic handlers, such as metrics collection and logging.
- [450](https://github.com/Shopify/job-iteration/pull/450) - Infer which interruption adapter to use from the queue adapter of the job. This deprecates setting `JobIteration.interruption_adapter = <callable>`, in favor of `JobIteration.register_interruption_adapter(<queue adapter name>, <callable>)`. `JobIteration.interruption_adapter` will be removed in a future release.

### Bug fixes

- [437](https://github.com/Shopify/job-iteration/pull/437) - Defer reading `JobIteration.max_job_runtime` until runtime, instead of closing around the value at the time of job definition.
- [431](https://github.com/Shopify/job-iteration/pull/431) - Use `#id_value` instead of `send(:id)`
when generating position for cursor based on `:id` column (Rails 7.1 and above, where composite
primary models are now supported). This ensures we grab the value of the id column, rather than a
potentially composite primary key value.
- [456](https://github.com/Shopify/job-iteration/pull/431) - Use Arel to generate SQL that's type compatible for the
  cursor pagination conditionals in ActiveRecord cursor. Previously, the cursor would coerce numeric ids to a string value 
  (e.g.: `... AND id > '1'`)

## v1.4.1 (Sep 5, 2023)

### Bug fixes

- [427](https://github.com/Shopify/job-iteration/pull/427) - Use the Rails application logger. Changes from [338](https://github.com/Shopify/job-iteration/pull/338) resulted in logging to the original value of ActiveJob.logger, not the one configured by the Rails application.

## v1.4.0 (Aug 23, 2023)

### Changes

- [338](https://github.com/Shopify/job-iteration/pull/338) - All logs are now `ActiveSupport::Notifications` events and logged using `ActiveSupport::LogSubscriber` to allow customization. Events now always include the `cursor_position` tag.
- [418](https://github.com/Shopify/job-iteration/pull/418) - Return `nil` from `Iteration#perform`, to signal not to rely on return value.

### Features

- [240](https://github.com/Shopify/job-iteration/pull/240) - Allow setting inheritable per-job `job_iteration_max_job_runtime`
- [310](https://github.com/Shopify/job-iteration/pull/310) - Support nested iteration
- [341](https://github.com/Shopify/job-iteration/pull/341) - Add `JobIteration.default_retry_backoff`, which sets a default delay when jobs are re-enqueued after being interrupted. Defaults to `nil`, meaning no delay, which matches the current behaviour.
- [365](https://github.com/Shopify/job-iteration/pull/365) - Support composite primary key as a cursor

### Bug fixes

- [289](https://github.com/Shopify/job-iteration/pull/289) - Fix uninitialized constant error when raising `ConditionNotSupportedError` from `ActiveRecordBatchEnumerator`
- [346](https://github.com/Shopify/job-iteration/pull/346) - Include failed jobs in `total_time`
- [417](https://github.com/Shopify/job-iteration/pull/417) - Ensure that numerical values are deserialized as such and not as strings.

## v1.3.6 (Mar 9, 2022)

- [190](https://github.com/Shopify/job-iteration/pull/190) - Fix updating `times_interrupted` and `total_time` when job is throttled

## v1.3.5 (Feb 10, 2022)

- [183](https://github.com/Shopify/job-iteration/pull/183) - Add `JobIteration::EnumeratorBuilder#build_csv_enumerator`

## v1.3.4 (Jan 18, 2022)

- [174](https://github.com/Shopify/job-iteration/pull/174) - Fix Ruby 3.2 compatibility

## v1.3.3 (Nov 17, 2021)
- [153](https://github.com/Shopify/job-iteration/pull/153) - Re-enqueue jobs only after shutdown hooks have run

## v1.3.2 (Nov 12, 2021)
- [148](https://github.com/Shopify/job-iteration/pull/148) - Revert "Do not evaluate enumerator when throttled", due to backwards incompatibility.

## v1.3.1 (Nov 11, 2021)
- [87](https://github.com/Shopify/job-iteration/pull/87) - Do not evaluate enumerator when throttled (REVERTED)


## v1.3.0 (Oct 7, 2021)
- [133](https://github.com/Shopify/job-iteration/pull/133) - Moves attributes out of JobIteration::Iteration included block


## v1.2.0 (Sept 21, 2021)
- [107](https://github.com/Shopify/job-iteration/pull/107) - Remove broken links from README
- [108](https://github.com/Shopify/job-iteration/pull/108) - Drop support for ruby 2.5
- [110](https://github.com/Shopify/job-iteration/pull/110) - Update rubocop TargetRubyVersion

## v1.1.14 (May 28, 2021)

#### Bug fix
- [84](https://github.com/Shopify/job-iteration/pull/84) - Call adjust_total_time before running on_complete callbacks
- [94](https://github.com/Shopify/job-iteration/pull/94) - Remove unnecessary break
- [95](https://github.com/Shopify/job-iteration/pull/95) - ActiveRecordBatchEnumerator#each should rewind at the end
- [97](https://github.com/Shopify/job-iteration/pull/97) - Batch enumerator size returns the number of batches, not records

## v1.1.13 (May 20, 2021)

#### New feature
- [91](https://github.com/Shopify/job-iteration/pull/91) - Add enumerator yielding batches as Active Record Relations

## v1.1.12 (April 19, 2021)

#### Bug fix

- [77](https://github.com/Shopify/job-iteration/pull/77) - Defer enforce cursor be serializable until 2.0.0

## v1.1.11 (April 19, 2021)

#### Bug fix

- [73](https://github.com/Shopify/job-iteration/pull/73) - Enforce cursor be serializable
  _This is reverted in 1.1.12 as it breaks behaviour in some apps._

## v1.1.10 (March 30, 2021)

- [69](https://github.com/Shopify/job-iteration/pull/69) - Fix memory leak in ActiveRecordCursor

## v1.1.9 (January 6, 2021)

- [61](https://github.com/Shopify/job-iteration/pull/61) - Call `super` in `method_added`

## v1.1.8 (June 8, 2020)

- Preserve ruby2_keywords tags in arguments on Ruby 2.7

## v1.1.7 (June 4, 2020)

- [54](https://github.com/Shopify/job-iteration/pull/54) - Fix warnings on Ruby 2.7

## v1.1.6 (May 22, 2020)

- [49](https://github.com/Shopify/job-iteration/pull/49) -  Log when enumerator has nothing to iterate
- [52](https://github.com/Shopify/job-iteration/pull/52) -  Fix CSVEnumerator cursor to properly remove already processed rows

## v1.1.5 (February 27, 2020)

- [47](https://github.com/Shopify/job-iteration/pull/47) -  Optional `sorbet-runtime` support for `JobIteration::Iteration` interface validation

## v1.1.4 (December 13, 2019)

- [45](https://github.com/Shopify/job-iteration/pull/45) -  Add Throttle enumerator


### v1.1.3 (August 20, 2019)

- [36](https://github.com/shopify/job-iteration/pull/39) -  Check method validation at job initialization step

### v1.1.2 (July 24, 2019)

#### Bug fix

- [36](https://github.com/shopify/job-iteration/pull/38) -  Fix CsvEnumerator for Ruby 2.6.3

### v1.1.1 (July 22, 2019)

#### Bug fix

- [36](https://github.com/shopify/job-iteration/pull/36) -  Add case for using default keyword arguments for cursor in #build_enumerator

### v1.1.0 (July 17, 2019)

#### New feature

- [35](https://github.com/Shopify/job-iteration/pull/35) - Raise exception if malformed arguments are use in #build_enumerator

### v1.0.0 (April 29, 2019)

It’s been in production at Shopify since 2017. It has support for Rails 5 and 6 :tada:

### Deprecations

- [34](https://github.com/Shopify/job-iteration/pull/34) - remove supports_interruption?

### Internal

- [30](https://github.com/Shopify/job-iteration/pull/30) - Better #each_iteration argument names

### v0.9.8 (December 5, 2018)

#### Bug fix

- [27](https://github.com/Shopify/job-iteration/pull/27) - iteration: don't allow double-retrying a job

### v0.9.7 (November 30, 2018)

#### New feature

- [23](https://github.com/shopify/job-iteration/pull/23) - Remove upperbound constraint on ActiveJob
