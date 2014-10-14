namespace :perf do
  task :setup do
    require 'benchmark/ips'
    require 'rack/file'
    require 'time'
    require 'rack/test'

    require 'get_process_mem'

    TEST_CNT         = (ENV['TEST_CNT'] || ENV['CNT'] || 1_000).to_i

    ENV["RAILS_ENV"] ||= "production"
    ENV['RACK_ENV']  = ENV["RAILS_ENV"]
    ENV["DISABLE_SPRING"] = "true"

    ENV["SECRET_KEY_BASE"] ||= "foofoofoo"

    ENV['LOG_LEVEL'] = "FATAL"

    '.:lib:test:config'.split(':').each { |x| $: << x }

    require 'application'

    Rails.env = ENV["RAILS_ENV"]

    APP = Rails.application
    # puts APP.method(:initialize!).source_location

    APP.initialize! unless APP.initialized?
    ActiveRecord::Migrator.migrations_paths = ActiveRecord::Tasks::DatabaseTasks.migrations_paths
    ActiveRecord::Migration.verbose = true
    ActiveRecord::Migrator.migrate(ActiveRecord::Migrator.migrations_paths, nil)

    APP.config.consider_all_requests_local = true


    @app = Rack::MockRequest.new(APP)

    puts "Booting: #{Rails.env}"

    if ENV["USE_SERVER"]
      @port = (3000..3900).to_a.sample
      thread = Thread.new do
        Rack::Server.start(app: APP, :Port => @port, environment: "none", server: "webrick")
      end
      sleep 1

      def call_app
        `curl http://localhost:#{@port} -s`
        raise "Bad request: #{response.body}" unless $?.success?
      end
    else
      def call_app
        response = @app.get("/")
        raise "Bad request: #{response.body}" unless response.status == 200
        response
      end
    end
  end


  desc "hits the url TEST_CNT times"
  task :test => [:setup] do
    Benchmark.bm { |x|
      x.report("#{TEST_CNT} requests") {
        TEST_CNT.times {
          call_app
        }
      }
    }
  end

  # desc "miniprofiler" do
  #  Rack::MiniProfiler.counter("slug") do
  #    Slug.for(title).presence || "topic"
  #  end
  # end

  desc "sampling stack time"
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

  task :kernel_requirepatch do
    require 'get_process_mem'

    module Kernel
      alias :original_require :require
      REQUIRE_HASH  = Hash.new { 0 }
      FILE_HASH     = Hash.new { 0 }

      def require file
        Kernel.require(file)
      end

      class << self
        alias :original_require :require
      end
    end
    Kernel.define_singleton_method(:require) do |file|
      name = file.split("/").first
      mem = GetProcessMem.new
      before = mem.mb
      original_require file
      after = mem.mb
      REQUIRE_HASH[name] += after - before
      FILE_HASH[file] = after - before
    end
  end

  desc "show memory usage caused by invoking require per gem"
  task :require_bench => [:kernel_requirepatch , :setup] do

    TEST_CNT.times {
      call_app
    }

    puts "require file [individual]: cost (mb)"
    puts "============"
    FILE_HASH.sort {|(k,v), (k2,v2)| v2 <=> v }.each do |k,v|
      puts "#{k}: #{v.round(2)}"
    end
    puts
    puts "file: cost (mb)"
    puts "=========="
    REQUIRE_HASH.sort {|(k,v), (k2,v2)| v2 <=> v }.each do |k,v|
      puts "#{k}: #{v.round(2)}"
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
        file = File.open("tmp/#{Time.now.iso8601}-#{ruby}-memory-#{TEST_CNT}-times.txt", 'w')
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

      TEST_CNT.times {
        call_app
      }
    ensure
      @keep_going = false
      ram_thread.join
      file.close unless ENV["SKIP_FILE_WRITE"]
    end
  end

  desc "ips"
  task :ips => [:setup] do
    Benchmark.ips do |x|
      x.report("ips") { call_app }
    end
  end

  desc "outputs GC::Profiler.report data while app is called TEST_CNT times"
  task :gc => [:setup] do
    GC::Profiler.enable
    TEST_CNT.times { call_app }
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

    # ObjectSpace.each_object do |obj|
    #   before[obj.class] += 1
    # end

    # module Kernel
    #   alias :original_caller_locations :caller_locations
    #   def caller_locations(*args)
    #     puts "========="
    #     puts caller
    #     original_caller_locations(*args)
    #   end
    # end

    TEST_CNT.times { call_app }

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

  desc "outputs allocated object diff after app is called TEST_CNT times"
  task :allocated_objects => [:setup] do
    call_app
    GC.start
    GC.disable
    start = ObjectSpace.count_objects
    TEST_CNT.times { call_app }
    finish = ObjectSpace.count_objects
    GC.enable
    finish.each do |k,v|
      puts k => (v - start[k]) / TEST_CNT.to_f
    end
  end


  desc "profiles ruby allocation"
  task :mem => [:setup] do
    require 'memory_profiler'
    call_app
    GC.start

    num = Integer(ENV["TEST_CNT"] || 1)
    opts = {}
    opts[:ignore_files] = /#{ENV['IGNORE_FILES_REGEXP']}/ if ENV['IGNORE_FILES_REGEXP']
    puts "Running #{num} times"
    report = MemoryProfiler.report(opts) do
      num.times { call_app }
    end
    report.pretty_print
  end

end
