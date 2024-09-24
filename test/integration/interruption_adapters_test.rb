# frozen_string_literal: true

require "test_helper"
require "open3"

class InterruptionAdaptersTest < ActiveSupport::TestCase
  test "successfully loads one (resque) interruption adapter" do
    ruby = <<~RUBY
      require 'bundler/setup'
      # Remove sidekiq, only resque will be left
      $LOAD_PATH.delete_if { |p| p =~ /sidekiq/ }
      require 'job-iteration'
      JobIteration::InterruptionAdapters.lookup(:resque)
    RUBY
    _stdout, stderr, status = run_ruby(ruby)

    assert_predicate(status, :success?)
    refute_match(/No interruption adapter is registered for :resque/, stderr)
  end

  test "does not load interruption adapter if queue adapter is not available" do
    ruby = <<~RUBY
      require 'bundler/setup'
      # Remove sidekiq, only resque will be left
      $LOAD_PATH.delete_if { |p| p =~ /sidekiq/ }
      require 'job-iteration'
      JobIteration::InterruptionAdapters.lookup(:sidekiq)
    RUBY
    _stdout, stderr, status = run_ruby(ruby)

    assert_predicate(status, :success?)
    assert_match(/No interruption adapter is registered for :sidekiq/, stderr)
  end

  test "loads all available interruption adapters" do
    ruby = <<~RUBY
      require 'bundler/setup'
      require 'job-iteration'
      # The adapter for GoodJob cannot be easily tested at the moment.
      addapters_to_test = JobIteration::InterruptionAdapters::BUNDLED_ADAPTERS - [:good_job]
      addapters_to_test.each do |name|
        JobIteration::InterruptionAdapters.lookup(name)
      end
    RUBY
    _stdout, stderr, status = run_ruby(ruby)

    assert_predicate(status, :success?)
    refute_match(/No interruption adapter is registered for/, stderr)
  end

  private

  def run_ruby(body)
    Tempfile.open do |f|
      f.write(body)
      f.close

      Open3.capture3("ruby", f.path)
    end
  end
end
