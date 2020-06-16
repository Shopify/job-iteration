# frozen_string_literal: true

source "https://rubygems.org"

git_source(:github) { |repo_name| "https://github.com/#{repo_name}" }

# Specify your gem's dependencies in job-iteration.gemspec
gemspec

# for integration testing
gem 'sidekiq'
gem 'resque'

gem 'mysql2', '~> 0.5'
gem 'globalid'
gem 'i18n'
gem 'redis'
gem 'database_cleaner'

gem 'pry'
gem 'byebug'
gem 'mocha'

gem 'rubocop', '~> 0.77.0'
gem 'yard'
gem 'rake'

# for unit testing optional sorbet support
gem 'sorbet-runtime'
