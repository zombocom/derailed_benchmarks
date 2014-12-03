require 'time'

require 'rack/test'
require 'rack/file'
require 'benchmark/ips'
require 'get_process_mem'

module DerailedBenchmarks
  def self.gem_is_bundled?(name)
    specs = Bundler.locked_gems.specs.each_with_object({}) {|spec, hash| hash[spec.name] = spec }
    specs[name]
  end
end

require 'derailed_benchmarks/require_tree'
