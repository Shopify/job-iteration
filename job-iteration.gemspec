
lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "job/iteration/version"

Gem::Specification.new do |spec|
  spec.name          = "job-iteration"
  spec.version       = Job::Iteration::VERSION
  spec.authors       = ["Shopify"]
  spec.email         = ["ops-accounts+shipit@shopify.com"]

  spec.summary       = %q{Makes your background jobs interruptible and resumable.}
  spec.description   = summary
  spec.homepage      = "https://github.com/shopify/job-iteration"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.16"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "minitest", "~> 5.0"
end
