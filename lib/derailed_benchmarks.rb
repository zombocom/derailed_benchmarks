require 'time'
require 'bundler'

require 'get_process_mem'

module DerailedBenchmarks
  def self.gem_is_bundled?(name)
    specs = ::Bundler.locked_gems.specs.each_with_object({}) {|spec, hash| hash[spec.name] = spec }
    specs[name]
  end

  class << self
    attr_accessor :auth
  end

  def self.add_auth(app)
    if use_auth = ENV['USE_AUTH']
      puts "Auth: #{use_auth}"
      auth.add_app(app)
    else
      app
    end
  end
end

require 'derailed_benchmarks/require_tree'
require 'derailed_benchmarks/auth_helper'

require 'derailed_benchmarks/stats_in_file'
require 'derailed_benchmarks/stats_from_dir'

if DerailedBenchmarks.gem_is_bundled?("devise")
  DerailedBenchmarks.auth = DerailedBenchmarks::AuthHelpers::Devise.new
end
