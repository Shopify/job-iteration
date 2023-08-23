# frozen_string_literal: true

lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "job-iteration/version"

Gem::Specification.new do |spec|
  spec.required_ruby_version = ">= 2.6"
  spec.name          = "job-iteration"
  spec.version       = JobIteration::VERSION
  spec.authors       = ["Shopify"]
  spec.email         = ["ops-accounts+shipit@shopify.com"]

  spec.summary       = "Makes your background jobs interruptible and resumable."
  spec.description   = spec.summary
  spec.homepage      = "https://github.com/shopify/job-iteration"
  spec.license       = "MIT"

  spec.files         = %x(git ls-files -z).split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.metadata["changelog_uri"] = "https://github.com/Shopify/job-iteration/blob/main/CHANGELOG.md"
  spec.metadata["allowed_push_host"] = "https://rubygems.org"

  spec.add_development_dependency("activerecord")
  spec.add_dependency("activejob", ">= 5.2")
end
