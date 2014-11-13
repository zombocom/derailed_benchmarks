namespace :perf do

  task :rails_load do
    TEST_COUNT         = (ENV['TEST_COUNT'] || ENV['CNT'] || 1_000).to_i

    ENV["RAILS_ENV"] ||= "production"
    ENV['RACK_ENV']  = ENV["RAILS_ENV"]
    ENV["DISABLE_SPRING"] = "true"

    ENV["SECRET_KEY_BASE"] ||= "foofoofoo"

    ENV['LOG_LEVEL'] = "FATAL"

    '.:lib:test:config'.split(':').each { |x| $: << x }

    require 'application'

    Rails.env = ENV["RAILS_ENV"]

    DERAILED_APP = Rails.application

    if DERAILED_APP.respond_to?(:initialized?)
      DERAILED_APP.initialize! unless DERAILED_APP.initialized?
    else
      DERAILED_APP.initialize! unless DERAILED_APP.instance_variable_get(:@initialized)
    end

    if defined? ActiveRecord
      ActiveRecord::Migrator.migrations_paths = DERAILED_APP.paths['db/migrate'].to_a
      ActiveRecord::Migration.verbose = true
      ActiveRecord::Migrator.migrate(ActiveRecord::Migrator.migrations_paths, nil)
    end

    DERAILED_APP.config.consider_all_requests_local = true
  end

  task :rack_load do
    puts "You're not using Rails"
    puts "You need to tell derailed how to boot your app"
    puts "In your perf.rake add:"
    puts
    puts "task :rack_load do"
    puts "  # DERAILED_APP = your code here"
    puts "end"
  end

  task :setup do
    require 'benchmark/ips'
    require 'rack/file'
    require 'time'
    require 'rack/test'
    require 'get_process_mem'

    specs = Bundler.locked_gems.specs.each_with_object({}) {|spec, hash| hash[spec.name] = spec }

    if specs["railties"]
      Rake::Task["perf:rails_load"].invoke
    else
      Rake::Task["perf:rack_load"].invoke
    end

    @app = Rack::MockRequest.new(DERAILED_APP)

    puts "Booting: #{Rails.env}"

    PATH_TO_HIT = ENV["PATH_TO_HIT"] || "/"
    if server = ENV["USE_SERVER"]
      @port = (3000..3900).to_a.sample
      thread = Thread.new do
        Rack::Server.start(app: DERAILED_APP, :Port => @port, environment: "none", server: server)
      end
      sleep 1

      def call_app
        `curl http://localhost:#{@port}#{PATH_TO_HIT} -s`
        raise "Bad request: #{response.body}" unless $?.success?
      end
    else
      def call_app
        response = @app.get(PATH_TO_HIT)
        raise "Bad request: #{response.body}" unless response.status == 200
        response
      end
    end
  end


  desc "hits the url TEST_COUNT times"
  task :test => [:setup] do
    Benchmark.bm { |x|
      x.report("#{TEST_COUNT} requests") {
        TEST_COUNT.times {
          call_app
        }
      }
    }
  end

  task :stackprof => [:setup] do
    # [:wall, :cpu, :object]
    require 'stackprof'
    file = "tmp/#{Time.now.iso8601}-stackprof-cpu-myapp.dump"
    StackProf.run(mode: :cpu, out: file) do
      Rake::Task["perf:test"].invoke
    end
    cmd = "stackprof #{file}"
    puts "Running `#{cmd}`. Execute `stackprof --help` for more info"
    puts `#{cmd}`
  end

  task :kernel_require_patch do
    require 'get_process_mem'

    class RequireTree
      attr_reader :name
      attr_accessor :cost

      def initialize(name)
        @name = name
        @children = {}
      end

      def <<(tree)
        @children[tree.name] = tree
      end

      def [](name)
        @children[name]
      end

      def children
        @children.values
      end

      def cost
        @cost || 0
      end

      def sorted_children
        children.sort { |c1, c2| c2.cost <=> c1.cost }
      end

      def print_sorted_children(level = 0)
        return if cost < ENV['CUT_OFF'].to_f
        puts "  " * level + "#{name}: #{cost.round(4)} mb"
        level += 1
        sorted_children.each do |child|
          child.print_sorted_children(level)
        end
      end
    end



    module Kernel
      alias :original_require :require
      REQUIRE_STACK = []

      def require file
        Kernel.require(file)
      end

      class << self
        alias :original_require :require
      end
    end

    TOP_REQUIRE = RequireTree.new("TOP")
    REQUIRE_STACK.push(TOP_REQUIRE)

    Kernel.define_singleton_method(:require) do |file|
      mem    = GetProcessMem.new
      node   = RequireTree.new(file)

      parent = REQUIRE_STACK.last
      parent << node
      REQUIRE_STACK.push(node)
      begin
        before = mem.mb
        original_require file
      ensure
        REQUIRE_STACK.pop # node
        after = mem.mb
      end
      node.cost = after - before
    end
  end

  desc "show memory usage caused by invoking require per gem"
  task :require_bench => [:kernel_require_patch , :setup] do
    ENV['CUT_OFF'] ||= "0.3"
    puts "## Impact of `require <file>` on RAM"
    puts
    puts "Showing all `require <file>` calls that consume #{ENV['CUT_OFF']} mb or more of RSS"
    puts "Configure with `CUT_OFF=0` for all entries or `CUT_OFF=5` for few entries"

    puts "Note: Files only count against RAM on their first load."
    puts "      If multiple libraries require the same file, then"
    puts "       the 'cost' only shows up under the first library"
    puts

    call_app

    TOP_REQUIRE.sorted_children.each do |child|
      child.print_sorted_children
    end
  end

  desc "outputs ram usage over time"
  task :ram_over_time => [:setup] do
    puts "PID: #{Process.pid}"
    ram = GetProcessMem.new
    @keep_going = true
    begin
      unless ENV["SKIP_FILE_WRITE"]
        ruby = `ruby -v`
        FileUtils.mkdir_p("tmp")
        file = File.open("tmp/#{Time.now.iso8601}-#{ruby}-memory-#{TEST_COUNT}-times.txt", 'w')
        file.sync = true
      end

      ram_thread = Thread.new do
        while @keep_going
          mb = ram.mb
          STDOUT.puts mb
          file.puts mb unless ENV["SKIP_FILE_WRITE"]
          sleep 5
        end
      end

      TEST_COUNT.times {
        call_app
      }
    ensure
      @keep_going = false
      ram_thread.join
      file.close unless ENV["SKIP_FILE_WRITE"]
    end
  end

  desc "iterations per second"
  task :ips => [:setup] do
    Benchmark.ips do |x|
      x.report("ips") { call_app }
    end
  end

  desc "outputs GC::Profiler.report data while app is called TEST_COUNT times"
  task :gc => [:setup] do
    GC::Profiler.enable
    TEST_COUNT.times { call_app }
    GC::Profiler.report
    GC::Profiler.disable
  end

  task :foo => [:setup] do
    require 'objspace'
    call_app

    before = Hash.new { 0 }
    after  = Hash.new { 0 }
    after_size = Hash.new { 0 }
    GC.start
    GC.disable

    TEST_COUNT.times { call_app }

    rvalue_size = GC::INTERNAL_CONSTANTS[:RVALUE_SIZE]
    ObjectSpace.each_object do |obj|
      after[obj.class] += 1
      memsize = ObjectSpace.memsize_of(obj) + rvalue_size
      # compensate for API bug
      memsize = rvalue_size if memsize > 100_000_000_000
      after_size[obj.class] += memsize
    end

    require 'pp'
    pp after.sort {|(k,v), (k2, v2)| v2 <=> v }
    puts "========="
    puts
    puts
    pp after_size.sort {|(k,v), (k2, v2)| v2 <=> v }
  end

  desc "outputs allocated object diff after app is called TEST_COUNT times"
  task :allocated_objects => [:setup] do
    call_app
    GC.start
    GC.disable
    start = ObjectSpace.count_objects
    TEST_COUNT.times { call_app }
    finish = ObjectSpace.count_objects
    GC.enable
    finish.each do |k,v|
      puts k => (v - start[k]) / TEST_COUNT.to_f
    end
  end


  desc "profiles ruby allocation"
  task :mem => [:setup] do
    require 'memory_profiler'
    call_app
    GC.start

    num = Integer(ENV["TEST_COUNT"] || 1)
    opts = {}
    opts[:ignore_files] = /#{ENV['IGNORE_FILES_REGEXP']}/ if ENV['IGNORE_FILES_REGEXP']
    puts "Running #{num} times"
    report = MemoryProfiler.report(opts) do
      num.times { call_app }
    end
    report.pretty_print
  end

end
