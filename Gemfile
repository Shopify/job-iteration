# frozen_string_literal: true

source "https://rubygems.org"

git_source(:github) { |repo_name| "https://github.com/#{repo_name}" }

# Specify your gem's dependencies in job-iteration.gemspec
gemspec

# for integration testing
gem 'appmap', :groups => [:development, :test]

gem "sidekiq"
gem "resque"

gem "mysql2", github: "brianmario/mysql2"
gem "globalid"
gem "i18n"
gem "redis"
gem "database_cleaner"

gem "pry"
gem "mocha"

gem "rubocop-shopify", require: false
gem "yard"
gem "rake"

# for unit testing optional sorbet support
gem "sorbet-runtime"
