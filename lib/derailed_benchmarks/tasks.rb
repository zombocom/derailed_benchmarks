namespace :perf do
  task :rails_load do
    ENV["RAILS_ENV"] ||= "production"
    ENV['RACK_ENV']  = ENV["RAILS_ENV"]
    ENV["DISABLE_SPRING"] = "true"

    ENV["SECRET_KEY_BASE"] ||= "foofoofoo"

    ENV['LOG_LEVEL'] = "FATAL"

    require 'rails'

    puts "Booting: #{Rails.env}"

    %W{ . lib test config }.each do |file|
      $LOAD_PATH << file
    end

    require 'application'

    Rails.env = ENV["RAILS_ENV"]

    DERAILED_APP = Rails.application

    if DERAILED_APP.respond_to?(:initialized?)
      DERAILED_APP.initialize! unless DERAILED_APP.initialized?
    else
      DERAILED_APP.initialize! unless DERAILED_APP.instance_variable_get(:@initialized)
    end

    if defined? ActiveRecord
      if defined? ActiveRecord::Tasks::DatabaseTasks
        ActiveRecord::Tasks::DatabaseTasks.create_current
      else # Rails 3.2
        raise "No valid database for #{ENV['RAILS_ENV']}, please create one" unless ActiveRecord::Base.connection.active?.inspect
      end

      ActiveRecord::Migrator.migrations_paths = DERAILED_APP.paths['db/migrate'].to_a
      ActiveRecord::Migration.verbose         = true
      ActiveRecord::Migrator.migrate(ActiveRecord::Migrator.migrations_paths, nil)
    end

    DERAILED_APP.config.consider_all_requests_local = true
  end

  task :rack_load do
    puts "You're not using Rails"
    puts "You need to tell derailed how to boot your app"
    puts "In your perf.rake add:"
    puts
    puts "namespace :perf do"
    puts "  task :rack_load do"
    puts "    # DERAILED_APP = your code here"
    puts "  end"
    puts "end"
  end

  task :setup do
    if DerailedBenchmarks.gem_is_bundled?("railties")
      Rake::Task["perf:rails_load"].invoke
    else
      Rake::Task["perf:rack_load"].invoke
    end

    TEST_COUNT  = (ENV['TEST_COUNT'] || ENV['CNT'] || 1_000).to_i
    PATH_TO_HIT = ENV["PATH_TO_HIT"] || ENV['ENDPOINT'] || "/"
    puts "Endpoint: #{ PATH_TO_HIT.inspect }"

    require 'rack/test'
    require 'rack/file'

    DERAILED_APP = DerailedBenchmarks.add_auth(DERAILED_APP)
    if server = ENV["USE_SERVER"]
      @port = (3000..3900).to_a.sample
      puts "Port: #{ @port.inspect }"
      puts "Server: #{ server.inspect }"
      thread = Thread.new do
        Rack::Server.start(app: DERAILED_APP, :Port => @port, environment: "none", server: server)
      end
      sleep 1

      def call_app(path = File.join("/", PATH_TO_HIT))
        cmd = "curl http://localhost:#{@port}#{path} -s --fail 2>&1"
        response = `#{cmd}`
        raise "Bad request to #{cmd.inspect} Response:\n#{ response.inspect }" unless $?.success?
      end
    else
      @app = Rack::MockRequest.new(DERAILED_APP)

      def call_app
        response = @app.get(PATH_TO_HIT)
        raise "Bad request: #{ response.body }" unless response.status == 200
        response
      end
    end
  end

  desc "hits the url TEST_COUNT times"
  task :test => [:setup] do
    require 'benchmark'

    Benchmark.bm { |x|
      x.report("#{TEST_COUNT} requests") {
        TEST_COUNT.times {
          call_app
        }
      }
    }
  end

  desc "stackprof"
  task :stackprof => [:setup] do
    # [:wall, :cpu, :object]
    begin
      require 'stackprof'
    rescue LoadError
      raise "Add stackprof to your gemfile to continue `gem 'stackprof', group: :development`"
    end
    TEST_COUNT = (ENV["TEST_COUNT"] ||= "100").to_i
    file = "tmp/#{Time.now.iso8601}-stackprof-cpu-myapp.dump"
    StackProf.run(mode: :cpu, out: file) do
      Rake::Task["perf:test"].invoke
    end
    cmd = "stackprof #{file}"
    puts "Running `#{cmd}`. Execute `stackprof --help` for more info"
    puts `#{cmd}`
  end

  task :kernel_require_patch do
    require 'derailed_benchmarks/core_ext/kernel_require.rb'
  end

  desc "show memory usage caused by invoking require per gem"
  task :mem => [:kernel_require_patch, :setup] do
    puts "## Impact of `require <file>` on RAM"
    puts
    puts "Showing all `require <file>` calls that consume #{ENV['CUT_OFF']} MiB or more of RSS"
    puts "Configure with `CUT_OFF=0` for all entries or `CUT_OFF=5` for few entries"

    puts "Note: Files only count against RAM on their first load."
    puts "      If multiple libraries require the same file, then"
    puts "       the 'cost' only shows up under the first library"
    puts

    call_app

    TOP_REQUIRE.print_sorted_children
  end

  desc "outputs memory usage over time"
  task :mem_over_time => [:setup] do
    require 'get_process_mem'
    puts "PID: #{Process.pid}"
    ram = GetProcessMem.new
    @keep_going = true
    begin
      unless ENV["SKIP_FILE_WRITE"]
        ruby = `ruby -v`.chomp
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

  task :ram_over_time do
    Kernel.warn("The ram_over_time task is deprecated. Use mem_over_time")
    Rake::Task["perf:ram_over_time"].invoke
  end

  desc "iterations per second"
  task :ips => [:setup] do
    require 'benchmark/ips'

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
  task :objects => [:setup] do
    require 'memory_profiler'
    call_app
    GC.start

    num = Integer(ENV["TEST_COUNT"] || 1)
    opts = {}
    opts[:ignore_files] = /#{ENV['IGNORE_FILES_REGEXP']}/ if ENV['IGNORE_FILES_REGEXP']
    opts[:allow_files]  = "#{ENV['ALLOW_FILES']}"         if ENV['ALLOW_FILES']

    puts "Running #{num} times"
    report = MemoryProfiler.report(opts) do
      num.times { call_app }
    end
    report.pretty_print
  end

  desc "heap analyzer"
  task :heap => [:setup] do
    require 'objspace'

    file_name = "tmp/#{Time.now.iso8601}-heap.dump"
    FileUtils.mkdir_p("tmp")
    ObjectSpace.trace_object_allocations_start
    puts "Running #{ TEST_COUNT } times"
    TEST_COUNT.times {
      call_app
    }
    GC.start

    puts "Heap file generated: #{ file_name.inspect }"
    ObjectSpace.dump_all(output: File.open(file_name, 'w'))

    require 'heapy'

    Heapy::Analyzer.new(file_name).analyze

    puts ""
    puts "Run `$ heapy --help` for more options"
    puts ""
    puts "Also try uploading #{file_name.inspect} to http://tenderlove.github.io/heap-analyzer/"
  end
end
