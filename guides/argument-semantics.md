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
Argumentative.perform_later(_arg1 = "One", _arg2 = "Two", _arg3 = "Three")
```

### Jobs with keyword arguments

Jobs with keyword arguments will have the keyword arguments available to both `build_enumerator` and `each_iteration`, but these arguments come packaged into a Hash in both cases. You will need to `fetch` or `[]` your parameter from the `Hash` you get passed in:

```ruby
class ParameterizedJob < ActiveJob::Base
  include JobIteration::Iteration

  def build_enumerator(kwargs, cursor:)
    name = kwargs.fetch(:name)
    email = kwargs.fetch(:email)
    # ...
  end

  def each_iteration(object_yielded_from_enumerator, kwargs)
    name = kwargs.fetch(:name)
    email = kwargs.fetch(:email)
    # ...
  end
end
```

To enqueue the job:

```ruby
ParameterizedJob.perform_later(name: "Jane", email: "jane@host.example")
```

Note that you cannot use `ruby2_keywords` at present.

### Jobs with both positional and keyword arguments

Jobs with keyword arguments will have the keyword arguments available to both `build_enumerator` and `each_iteration`, but these arguments come packaged into a Hash in both cases. You will need to `fetch` or `[]` your parameter from the `Hash` you get passed in:

```ruby
class HighlyConfigurableGreetingJob < ActiveJob::Base
  include JobIteration::Iteration

  def build_enumerator(subject_line, kwargs, cursor:)
    name = kwargs.fetch(:sender_name)
    email = kwargs.fetch(:sender_email)
    # ...
  end

  def each_iteration(object_yielded_from_enumerator, subject_line, kwargs)
    name = kwargs.fetch(:sender_name)
    email = kwargs.fetch(:sender_email)
    # ...
  end
end
```

To enqueue the job:

```ruby
HighlyConfigurableGreetingJob.perform_later(_subject_line = "Greetings everybody!", sender_name: "Jane", sender_email: "jane@host.example")
```

Note that you cannot use `ruby2_keywords` at present.

### Returning (yielding) from enumerators

When defining a custom enumerator (see the [custom enumerator guide](custom-enumerator.md)) you need to yield two positional arguments from it: the object that will be value for the current iteration (like a single ActiveModel instance, a single number...) and value you want to be persisted as the `cursor` value should `job-iteration` decide to interrupt you. That new `cursor` value does not get passed to `each_iteration`:

```ruby
Enumerator.new do |yielder|
  # In this case `cursor` is an Integer
  cursor.upto(99999) do |offset|
    yielder.yield(fetch_record_at(offset), offset)
  end
end
```
