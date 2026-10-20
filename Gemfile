# frozen_string_literal: true

source "https://rubygems.org"

git_source(:github) { |repo_name| "https://github.com/#{repo_name}" }

# Specify your gem's dependencies in job-iteration.gemspec
gemspec

rails_version = ENV.fetch("RAILS_VERSION", "edge") == "edge" ? Gem::Version.new("8.2") : Gem::Version.new(ENV.fetch("RAILS_VERSION"))

resque_version = if rails_version < Gem::Version.new("7.2")
  "< 3.0.0" # Resque 3.0.0 requires Rails 7.2 or later
else
  ">= 3.0.0"
end

# for integration testing
gem "sidekiq", ">= 8.0.9" # Fixes incompatibility with connection_pool >= 3.0.0
gem "resque", resque_version
gem "delayed_job"
gem "connection_pool", ">= 3.0.0"

if defined?(@rails_gems_requirements) && @rails_gems_requirements
  # We avoid the `gem "..."` syntax here so Dependabot doesn't try to update these gems.
  [
    "activejob",
    "activerecord",
    "railties",
  ].each { |name| gem name, @rails_gems_requirements }
else
  # gem "activejob" # Set in gemspec
  gem "activerecord"
  gem "railties"
end

gem "mysql2", github: "brianmario/mysql2"
gem "globalid"
gem "i18n"
gem "redis"

gem "pry"
gem "mocha"

gem "rubocop-shopify", require: false
gem "yard"
gem "rake"
gem "csv" # required for Ruby 3.4+
gem "mutex_m" # Required for Ruby 3.4+

gem "json", ">= 3"

# for unit testing optional sorbet support
gem "sorbet-runtime", ">= 0.6.12698"
gem "tapioca", ">= 0.20"

gem "logger"
