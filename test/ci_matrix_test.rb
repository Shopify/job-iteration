# frozen_string_literal: true

require "test_helper"
require "yaml"

module JobIteration
  class CiMatrixTest < ActiveSupport::TestCase
    test "Required Ruby version in gemspec matches oldest Ruby in CI matrix" do
      assert_equal(
        oldest_ruby_in_matrix,
        required_ruby_version,
        "Required Ruby version in gemspec does not match oldest Ruby in CI matrix",
      )
    end

    test "Dev Ruby version matches the newest Ruby in CI matrix" do
      assert_equal(
        newest_ruby_in_matrix,
        ruby_version_for_development,
        "Development does not use the newest Ruby in CI matrix",
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

    def ruby_version_for_development
      File
        .read(".ruby-version")
        .strip
        .then { |ruby_version| ignoring_patch(Gem::Version.new(ruby_version)) }
    end

    def required_ruby_version
      Gem
        .loaded_specs
        .fetch("job-iteration")
        .required_ruby_version
        .to_s[/(?<=>= )\d+\.\d+/]
        .then { |ruby_version| ignoring_patch(Gem::Version.new(ruby_version)) }
    end

    # Our CI matrix only specfies major and minor versions of Ruby
    def ignoring_patch(version)
      Gem::Version.new(version.segments[0, 2].join("."))
    end
  end
end
