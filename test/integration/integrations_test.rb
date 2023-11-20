# frozen_string_literal: true

require "test_helper"
require "open3"

class IntegrationsTest < ActiveSupport::TestCase
  test "will prevent loading two integrations" do
    with_env("ITERATION_DISABLE_AUTOCONFIGURE", nil) do
      ruby = <<~RUBY
        require 'bundler/setup'
        require 'job-iteration'
      RUBY
      _stdout, stderr, status = run_ruby(ruby)

      assert_equal false, status.success?
      assert_match(/resque integration has already been loaded, but sidekiq is also available/, stderr)
    end
  end

  test "successfully loads one (resque) integration" do
    with_env("ITERATION_DISABLE_AUTOCONFIGURE", nil) do
      ruby = <<~RUBY
        require 'bundler/setup'
        # Remove sidekiq, only resque will be left
        $LOAD_PATH.delete_if { |p| p =~ /sidekiq/ }
        require 'job-iteration'
      RUBY
      _stdout, _stderr, status = run_ruby(ruby)

      assert_equal true, status.success?
    end
  end

  private

  def run_ruby(body)
    stdout, stderr, status = nil
    Tempfile.open do |f|
      f.write(body)
      f.close

      command = "ruby #{f.path}"
      stdout, stderr, status = Open3.capture3(command)
    end
    [stdout, stderr, status]
  end

  def with_env(variable, value)
    original = ENV[variable]
    ENV[variable] = value
    yield
  ensure
    ENV[variable] = original
  end
end
