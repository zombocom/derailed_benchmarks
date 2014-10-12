namespace :perf do
  task :setup do
    require 'benchmark/ips'
    require 'rack/file'
    require 'rack/test'

    TEST_CNT         = (ENV['TEST_CNT'] || ENV['CNT'] || 1_000).to_i
    ENV["RAILS_ENV"] ||= "production"
    ENV['RACK_ENV']  = ENV["RAILS_ENV"]
    ENV["DISABLE_SPRING"] = "true"

    ENV["SECRET_KEY_BASE"] ||= "foofoofoo"

    ENV['LOG_LEVEL'] = "FATAL"

    '.:lib:test:config'.split(':').each { |x| $: << x }

    require 'application'

    APP = Rails.application

    APP.initialize! unless APP.initialized?
    ActiveRecord::Migrator.migrations_paths = ActiveRecord::Tasks::DatabaseTasks.migrations_paths
    ActiveRecord::Migration.verbose = true
    ActiveRecord::Migrator.migrate(ActiveRecord::Migrator.migrations_paths, nil)

    APP.config.consider_all_requests_local = true


    @app = Rack::MockRequest.new(APP)

    puts "Booting: #{Rails.env}"

    if ENV["USE_SERVER"]
      thread = Thread.new do
        Rack::Server.start(app: APP, :Port => 3000, environment: "none")
      end
      sleep 1

      def call_app
        `curl http://localhost:3000 -s`
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

  desc "outputs ram usage over time"
  task :ram_over_time => [:setup] do
    puts "PID: #{Process.pid}"
    ram = GetProcessMem.new
    @keep_going = true
    begin
      unless ENV["SKIP_FILE_WRITE"]
        ruby = `ruby -v`
        file = File.open("#{Time.now}-#{ruby}-memory-#{TEST_CNT}-times.txt", 'w')
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
      p k => (v - start[k]) / TEST_CNT.to_f
    end
  end


  desc "profiles ruby allocation"
  task :mem => [:setup] do
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
