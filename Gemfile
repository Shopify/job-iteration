# frozen_string_literal: true

source "https://rubygems.org"

git_source(:github) { |repo_name| "https://github.com/#{repo_name}" }

# Specify your gem's dependencies in job-iteration.gemspec
gemspec

# for integration testing
gem "sidekiq"
gem "resque"
gem "delayed_job"

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

ruby_version = Gem::Version.new(RUBY_VERSION)
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
