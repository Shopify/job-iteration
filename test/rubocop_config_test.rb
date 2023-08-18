# frozen_string_literal: true

require "test_helper"
require "yaml"

module JobIteration
  class RubocopConfigTest < ActiveSupport::TestCase
    test "TargetRubyVersion in .rubocop.yml matches oldest Ruby in CI matrix" do
      assert_equal(
        oldest_ruby_in_matrix,
        target_ruby_version,
        "TargetRubyVersion in .rubocop.yml does not match oldest Ruby in CI matrix",
      )
    end

    test "Linting runs on the newest Ruby in CI matrix" do
      assert_equal(
        newest_ruby_in_matrix,
        ruby_version_for_linting,
        "Linting does not run on the newest Ruby in CI matrix",
      )
    end

    test "TargetRubyVersion in .rubocop.yml matches required Ruby version in gemspec" do
      assert_equal(
        required_ruby_version,
        target_ruby_version,
        "TargetRubyVersion in .rubocop.yml does not match required Ruby version in gemspec",
      )
    end

    private

    def oldest_ruby_in_matrix
      ruby_versions_in_matrix.min
    end

    def newest_ruby_in_matrix
      ruby_versions_in_matrix.max
    end

    def ruby_versions_in_matrix
      YAML
        .load_file(".github/workflows/ci.yml")
        .dig("jobs", "build", "strategy", "matrix", "ruby")
        .tap { |ruby_versions| refute_nil(ruby_versions, "Ruby versions not found in CI matrix") }
        .map { |ruby_version| Gem::Version.new(ruby_version) }
    end

    def ruby_version_for_linting
      YAML
        .load_file(".github/workflows/ci.yml")
        .dig("jobs", "lint", "steps")
        .tap { |steps| refute_nil(steps, "Steps not found in linting CI config") }
        .find { |step| step.fetch("uses", "") =~ %r{^ruby/setup-ruby} }
        .tap { |step| refute_nil(step, "Ruby setup step not found in linting CI config") }
        .then { |step| step.dig("with", "ruby-version") }
        .tap { |ruby_version| refute_nil(ruby_version, "Ruby version not found in linting CI config") }
        .then { |ruby_version| Gem::Version.new(ruby_version) }
    end

    def target_ruby_version
      YAML
        .load_file(".rubocop.yml")
        .dig("AllCops", "TargetRubyVersion")
        .tap { |ruby_version| refute_nil(ruby_version, "TargetRubyVersion not found in .rubocop.yml") }
        .then { |ruby_version| Gem::Version.new(ruby_version) }
    end

    def required_ruby_version
      Gem
        .loaded_specs
        .fetch("job-iteration")
        .required_ruby_version
        .to_s[/(?<=>= )\d+\.\d+/]
        .then { |ruby_version| Gem::Version.new(ruby_version) }
    end
  end
end
