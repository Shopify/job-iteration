# frozen_string_literal: true

require "test_helper"
require "tempfile"
require "fileutils"
require "open3"

class RailsIntegrationTest < ActiveSupport::TestCase
  CommandFailed = Class.new(StandardError)

  test "running a job in a Rails app works" do
    # This test is slow, because it has to install gems and generate an entire Rails app.
    in_dummy_rails_app_with_job_iteration do |_dir|
      puts "Writing app/jobs/example_job.rb" if ENV["DEBUG"]
      File.write("app/jobs/example_job.rb", <<~RUBY)
        class ExampleJob < ApplicationJob
          include JobIteration::Iteration

          def build_enumerator(cursor:)
            enumerator_builder.array(["it works"], cursor: cursor)
          end

          def each_iteration(string)
            puts string
          end
        end
      RUBY

      output = run_or_raise("bin/rails", "runner", "ExampleJob.perform_now")
      assert_includes(output, "it works")
    end
  end

  private

  def in_dummy_rails_app_with_job_iteration
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do |dir|
        dir = File.join(dir, "dummy")
        FileUtils.mkdir(dir)
        Dir.chdir(dir) do |dir|
          with_env(ENV.reject { |k, _v| k == "BUNDLE_GEMFILE" }) do # Don't use the Gemfile override set in CI.
            run_or_raise("bundle", "init")

            # It is unclear why we need to do this, but otherwise it blows up with:
            #   Could not find <the gems below> in any of the sources (Bundler::GemNotFound)
            run_or_raise("gem", "install", "nio4r")
            run_or_raise("gem", "install", "websocket-driver")
            run_or_raise("gem", "install", "date")
            run_or_raise("gem", "install", "racc")

            # It is also unclear why we need to --skip-install, lock, and install, instead of just using `bundle add`,
            # but, again, otherwise it blows up with the same error as above.
            run_or_raise("bundle", "add", "rails", "--version", rails_version.to_s, "--skip-install")
            run_or_raise("bundle", "lock")
            run_or_raise("bundle", "install")

            run_or_raise(
              "rails",
              "new",
              ".",
              "--force",
              # We should switch to `--minimal --no-skip-active-job` once the oldest supported Rails version supports it
              # https://github.com/rails/rails/blob/a4581b53aae93a8dd3205abae0630398cbce9204/railties/lib/rails/generators/app_base.rb#L35-L88
              "--skip-yarn",
              "--skip-git",
              "--skip-action-mailer",
              "--skip-action-storage",
              "--skip-puma",
              "--skip-action-cable",
              "--skip-sprockets",
              "--skip-spring",
              "--skip-listen",
              "--skip-coffee",
              "--skip-javascript",
              "--skip-test",
              "--skip-system-test",
              "--skip-bootsnap",
            )
            # `bundle add` doesn't support path: sources, so we'll append it manually
            puts "Simulating `bundle add job-iteration` with path: to this repo." if ENV["DEBUG"]
            File.open("Gemfile", "a") { |f| f.puts "gem 'job-iteration', path: '#{Bundler.root}'" }
            run_or_raise("bundle", "install")

            yield dir
          end
        end
      end
    end
  end

  def run_or_raise(*args, **kwargs, &block)
    puts "Running: #{args.join(" ")}" if ENV["DEBUG"]

    stdout_and_stderr, status = Open3.capture2e(
      # ENV.to_hash.merge({"COLUMNS" => "1000"})
      { "COLUMNS" => "1000" }, # Otherwise output is weirdly wrapped.
      *args,
      **kwargs,
      &block
    )
    raise CommandFailed, stdout_and_stderr unless status.success?

    puts stdout_and_stderr if ENV["DEBUG"]

    stdout_and_stderr
  end

  def rails_version
    # We're going to install Rails in the dummy app, so we need to know the version to install.
    # We don't depend on Rails though, so read the version of Active Support instead, since they always match.
    Gem.loaded_specs.fetch("activesupport").version
  end

  def with_env(env)
    original_env = ENV.to_hash
    ENV.replace(env)
    yield
  ensure
    ENV.replace(original_env)
  end
end
