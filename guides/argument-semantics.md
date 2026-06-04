`job-iteration` overrides the `perform` method of `ActiveJob::Base` to allow for iteration. The `perform` method preserves all the standard calling conventions of the original, but the way the subsequent methods work might differ from what one expects from an ActiveJob subclass.

The call sequence is usually 3 methods:

`perform -> build_enumerator -> each_iteration|each_batch`

In that sense `job-iteration` works like a framework (it calls your code) rather than like a library (that you call). When using jobs with parameters, the following rules of thumb are good to keep in mind.

### Jobs without arguments

Jobs without arguments do not pass anything into either `build_enumerator` or `each_iteration` except for the `cursor` which `job-iteration` persists by itself:

```ruby
class ArglessJob < ActiveJob::Base
  include JobIteration::Iteration

  def build_enumerator(cursor:)
    # ...
  end

  def each_iteration(single_object_yielded_from_enumerator)
    # ...
  end
end
```

To enqueue the job:

```ruby
ArglessJob.perform_later
```

### Jobs with positional arguments

Jobs with positional arguments will have those arguments available to both `build_enumerator` and `each_iteration`:

```ruby
class ArgumentativeJob < ActiveJob::Base
  include JobIteration::Iteration

  def build_enumerator(arg1, arg2, arg3, cursor:)
    # ...
  end

  def each_iteration(single_object_yielded_from_enumerator, arg1, arg2, arg3)
    # ...
  end
end
```

To enqueue the job:

```ruby
ArgumentativeJob.perform_later(_arg1 = "One", _arg2 = "Two", _arg3 = "Three")
```

### Jobs with keyword arguments

Jobs with keyword arguments can declare those keyword arguments directly on both `build_enumerator` and `each_iteration`:

```ruby
class ParameterizedJob < ActiveJob::Base
  include JobIteration::Iteration

  def build_enumerator(name:, email:, cursor:)
    # ...
  end

  def each_iteration(object_yielded_from_enumerator, name:, email:)
    # ...
  end
end
```

To enqueue the job:

```ruby
ParameterizedJob.perform_later(name: "Jane", email: "jane@host.example")
```

The `cursor:` keyword argument on `build_enumerator` is reserved for `job-iteration`; do not pass a job argument named `cursor` when using keyword arguments.

For compatibility with existing jobs, keyword arguments are still passed as a positional params Hash after any positional arguments when `build_enumerator` and `each_iteration` do not declare keyword arguments (other than `cursor` for `build_enumerator`). This compatibility path is transitional and will be removed in a future release; prefer declaring keyword arguments directly instead of combining a positional params Hash with `perform_later(keyword: value)`:

```ruby
class LegacyParameterizedJob < ActiveJob::Base
  include JobIteration::Iteration

  def build_enumerator(params, cursor:)
    name = params.fetch(:name)
    email = params.fetch(:email)
    # ...
  end

  def each_iteration(object_yielded_from_enumerator, params)
    name = params.fetch(:name)
    email = params.fetch(:email)
    # ...
  end
end
```

### Returning (yielding) from enumerators

When defining a custom enumerator (see the [custom enumerator guide](custom-enumerator.md)) you need to yield two positional arguments from it: the object that will be the value for the current iteration (like a single ActiveModel instance, a single number...) and the value you want to be persisted as the `cursor` value should `job-iteration` decide to interrupt you after this iteration. Calling the enumerator with that cursor should return the next object after the one returned in this iteration. That new `cursor` value does not get passed to `each_iteration`:

```ruby
Enumerator.new do |yielder|
  # In this case `cursor` is an Integer
  cursor.upto(99999) do |offset|
    yielder.yield(fetch_record_at(offset), offset)
  end
end
```
