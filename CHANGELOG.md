### Master (unreleased)

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
