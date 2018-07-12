# Best practices

## Instrumentation

Iteration leverages `ActiveSupport::Notifications` which lets you instrument all kind of events:

```ruby
# config/initializers/instrumentation.rb
ActiveSupport::Notifications.subscribe('build_enumerator.iteration') do |_, started, finished, _, tags|
  StatsD.distribution(
    'iteration.build_enumerator',
    (finished - started),
    tags: { job_class: tags[:job_class]&.underscore }
  )
end

ActiveSupport::Notifications.subscribe('each_iteration.iteration') do |_, started, finished, _, tags|
  elapsed = finished - started
  StatsD.distribution(
    "iteration.each_iteration",
    elapsed,
    tags: { job_class: tags[:job_class]&.underscore }
  )

  if elapsed >= BackgroundQueue.max_iteration_runtime
    Rails.logger.warn "[Iteration] job_class=#{tags[:job_class]} " \
    "each_iteration runtime exceeded limit of #{BackgroundQueue.max_iteration_runtime}s"
  end
end

ActiveSupport::Notifications.subscribe('resumed.iteration') do |_, _, _, _, tags|
  StatsD.increment(
    "iteration.resumed",
    tags: { job_class: tags[:job_class]&.underscore }
  )
end

ActiveSupport::Notifications.subscribe('interrupted.iteration') do |_, _, _, _, tags|
  StatsD.increment(
    "iteration.interrupted",
    tags: { job_class: tags[:job_class]&.underscore }
  )
end
```

## Max iteration time

As you may notice in the snippet above, at Shopify we enforce that `each_iteration` does not take longer than `BackgroundQueue.max_iteration_runtime`, which is set to `25` seconds.

We discourage that because jobs with a long `each_iteration` make interruptibility somewhat useless, as the infrastructure will have to wait longer for the job to interrupt.

## Max job runtime

If a job is supposed to have millions of iterations and you expect it to run for hours and days, it's still a good idea to sometimes interrupt the job even if there are no interruption signals coming from deploys or the infrastructure. At Shopify, we interrupt at least every 5 minutes to preserve **worker capacity**.

```ruby
JobIteration.max_job_runtime = 5.minutes # nil by default
```

Use this accessor to tweak how often you'd like the job to interrupt itself.
