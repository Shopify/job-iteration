### Master (unreleased)

#### New feature

#### Bug fix

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
