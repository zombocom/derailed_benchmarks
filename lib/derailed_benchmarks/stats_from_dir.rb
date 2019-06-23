require 'bigdecimal'
require 'statistics'

module DerailedBenchmarks
  # A class used to read several benchmark files
  # it will parse each file, then sort by average
  # time of benchmarks. It can be used to find
  # the fastest and slowest examples and give information
  # about them such as what the percent difference is
  # and if the results are statistically significant
  #
  # Example:
  #
  #   stats = StatsFromDir.new("path/to/dir")
  #   stats.fastest.average # => 10.5
  #   stats.slowest.average # => 11.0
  #   stats.significant?    # => true
  #   stats.x_faster        # => "1.0476"
  class StatsFromDir
    FORMAT = "%0.4f"
    attr_reader :stats

    def initialize(dir)
      @dir = dir
      @file_hash = {}
      @files = []

      dir = File.expand_path(dir)

      Dir.entries(dir).each do |entry|
        file_name = File.join(dir, entry)
        next if File.directory?(file_name)

        @files << StatsForFile.new(file_name)
      end

      raise "No files found in '#{dir}'" if @files.empty?

      @files.sort_by! { |f| f.average }
      @stats = students_t_test
    end

    def students_t_test(series_1=fastest.values, series_2=slowest.values)
      StatisticalTest::TTest.perform(
        alpha = 0.05,
        :two_tail,
        series_1,
        series_2
      )
    end

    def fastest
      @files.first
    end

    def slowest
      @files.last
    end

    def significant?
      @stats[:alternative]
    end

    def p_value
      @stats[:p_value].to_f
    end

    def x_faster
      faster = fastest.average
      slower = slowest.average

      FORMAT % (slower/faster).to_f
    end

    def percent_faster
      faster = fastest.average
      slower = slowest.average
      FORMAT % (((slower - faster) / slower).to_f  * 100)
    end

    def banner(io = Kernel)
      if significant?
        io.puts "❤️ " * 40
      else
        io.puts "👎 " * 40
      end
      io.puts
      io.puts "Test #{fastest.name.inspect} is faster than #{slowest.name.inspect} by"
      io.puts "  #{x_faster}x faster or #{percent_faster}\% faster"
      io.puts ""
      io.puts "P-value: #{p_value}"
      io.puts "Is signifigant? (P-value < 0.05): #{significant?}"
    end
  end
end
