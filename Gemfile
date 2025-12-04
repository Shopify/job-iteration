# frozen_string_literal: true

source "https://rubygems.org"

git_source(:github) { |repo_name| "https://github.com/#{repo_name}" }

# Specify your gem's dependencies in job-iteration.gemspec
gemspec

ruby_version = Gem::Version.new(RUBY_VERSION)
rails_version = ENV.fetch("RAILS_VERSION", "edge") == "edge" ? Gem::Version.new("8.2") : Gem::Version.new(ENV.fetch("RAILS_VERSION"))

if ruby_version >= Gem::Version.new("3.2") && rails_version >= Gem::Version.new("7.1")
  sidekiq_version = ">= 8.0.9" # Fixes incompatibility with connection_pool >= 3.0.0, but is not compatible with Rails 7.0
  connection_pool_version = ">= 3.0.0"
else
  sidekiq_version = ">= 7.0.0"
  connection_pool_version = "< 3.0.0"
end

# for integration testing
gem "sidekiq", sidekiq_version
gem "resque"
gem "delayed_job"
gem "connection_pool", connection_pool_version

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

if ruby_version >= Gem::Version.new("3.2")
  tapioca_version = ">= 0.17.9" # Fixes incompatibility with Sorbet >= 0.6.12698
  sorbet_version = ">= 0.6.12698"
else
  tapioca_version = ">= 0.10.0"
  sorbet_version = "< 0.6.12698"
end

# for unit testing optional sorbet support
gem "sorbet-runtime", sorbet_version
gem "tapioca", tapioca_version

gem "logger"
