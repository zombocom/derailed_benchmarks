require_relative 'load_tasks'

namespace :perf do
  desc "hits the url TEST_COUNT times"
  task :test => [:setup] do
    require 'benchmark'

    Benchmark.bm { |x|
      x.report("#{TEST_COUNT} derailed requests") {
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
    raise "Use mem_over_time"
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
