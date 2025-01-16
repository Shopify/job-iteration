# frozen_string_literal: true

source "https://rubygems.org"

git_source(:github) { |repo_name| "https://github.com/#{repo_name}" }

# Specify your gem's dependencies in job-iteration.gemspec
gemspec

# for integration testing
gem "sidekiq"
gem "resque"

if defined?(@rails_gems_requirements) && @rails_gems_requirements
  # We avoid the `gem "..."` syntax here so Dependabot doesn't try to update these gems.
  [
    "activejob",
    "activerecord",
  ].each { |name| gem name, @rails_gems_requirements }
else
  # gem "activejob" # Set in gemspec
  gem "activerecord"
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

# for unit testing optional sorbet support
gem "sorbet-runtime"

gem "logger"
