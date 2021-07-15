# frozen_string_literal: true

require "test_helper"
require "open3"

class IntegrationsTest < ActiveSupport::TestCase
  test "successfully loads one (resque) integration" do
    with_env("ITERATION_DISABLE_AUTOCONFIGURE", nil) do
      rubby = <<~RUBBY
        require 'bundler/setup'
        # Remove sidekiq, only resque will be left
        $LOAD_PATH.delete_if { |p| p =~ /sidekiq/ }
        require 'job_iteration'
      RUBBY
      _stdout, _stderr, status = run_ruby(rubby)

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
