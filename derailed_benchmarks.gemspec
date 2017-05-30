# -*- encoding: utf-8 -*-
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'derailed_benchmarks/version'

Gem::Specification.new do |gem|
  gem.name          = "derailed_benchmarks"
  gem.version       = DerailedBenchmarks::VERSION
  gem.authors       = ["Richard Schneeman"]
  gem.email         = ["richard.schneeman+rubygems@gmail.com"]
  gem.description   = %q{ Go faster, off the Rails }
  gem.summary       = %q{ Benchmarks designed to performance test your ENTIRE site }
  gem.homepage      = "https://github.com/schneems/derailed_benchmarks"
  gem.license       = "MIT"

  gem.files         = `git ls-files`.split($/)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.require_paths = ["lib"]

  gem.required_ruby_version = ">= 2.1.0"

  gem.add_dependency "heapy",           "~> 0"
  gem.add_dependency "memory_profiler", "~> 0"
  gem.add_dependency "get_process_mem", "~> 0"
  gem.add_dependency "benchmark-ips",   "~> 2"
  gem.add_dependency "rack",            ">= 1"
  gem.add_dependency "rake",            "> 10", "< 13"
  gem.add_dependency "thor",            "~> 0.19"

  gem.add_development_dependency "capybara",  "~> 2"
  gem.add_development_dependency "rails",     "> 3", "< 6"
  gem.add_development_dependency "devise",    "> 3", "< 5"
  gem.add_development_dependency "appraisal", "2.2.0"
end
