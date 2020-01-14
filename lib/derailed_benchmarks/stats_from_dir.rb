# frozen_string_literal: true

require 'bigdecimal'
require 'statistics'
require 'unicode_plot'
require 'stringio'

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
  #   branch_info = {}
  #   branch_info["loser"]  = { desc: "Old commit", time: Time.now, file: dir.join("loser.bench.txt"), name: "loser" }
  #   branch_info["winner"] = { desc: "I am the new commit", time: Time.now + 1, file: dir.join("winner.bench.txt"), name: "winner" }
  #   stats = DerailedBenchmarks::StatsFromDir.new(branch_info)
  #
  #   stats.newest.average  # => 10.5
  #   stats.oldest.average  # => 11.0
  #   stats.significant?    # => true
  #   stats.x_faster        # => "1.0476"
  class StatsFromDir
    FORMAT = "%0.4f"
    attr_reader :stats, :oldest, :newest

    def initialize(hash)
      @files = []

      hash.each do |branch, info_hash|
        file = info_hash.fetch(:file)
        desc = info_hash.fetch(:desc)
        time = info_hash.fetch(:time)
        @files << StatsForFile.new(file: file, desc: desc, time: time, name: branch)
      end
      @files.sort_by! { |f| f.time }
      @oldest = @files.first
      @newest = @files.last
    end

    def call
      @files.each(&:call)

      stats_95 = statistical_test(confidence: 95)

      # If default check is good, see if we also pass a more rigorous test
      # if so, then use the more rigourous test
      if stats_95[:alternative]
        stats_99 = statistical_test(confidence: 99)
        @stats = stats_99 if stats_99[:alternative]
      end
      @stats ||= stats_95

      self
    end

    def statistical_test(series_1=oldest.values, series_2=newest.values, confidence: 95)
      StatisticalTest::KSTest.two_samples(
        group_one: series_1,
        group_two: series_2,
        alpha: (100 - confidence) / 100.0
      )
    end

    def significant?
      @stats[:alternative]
    end

    def d_max
      @stats[:d_max].to_f
    end

    def d_critical
      @stats[:d_critical].to_f
    end

    def x_faster
      (oldest.median/newest.median).to_f
    end

    def faster?
      newest.median < oldest.median
    end

    def percent_faster
      (((oldest.median - newest.median) / oldest.median).to_f  * 100)
    end

    def change_direction
      if faster?
        "FASTER 🚀🚀🚀"
      else
        "SLOWER 🐢🐢🐢"
      end
    end

    def align
      " " * (percent_faster.to_s.index(".") - x_faster.to_s.index("."))
    end

    def histogram(io = $stdout)
      [newest, oldest].each do |report|
        plot = UnicodePlot.histogram(
          report.values,
          title: "\nHistogram - [#{report.name}] #{report.desc.inspect}",
          ylabel: "Time (seconds)",
          xlabel: "# of runs in range"
        )
        plot.render(io)
        io.puts
      end

      io.puts
    end

    def banner(io = $stdout)
      io.puts
      if significant?
        io.puts "❤️ ❤️ ❤️  (Statistically Significant) ❤️ ❤️ ❤️"
      else
        io.puts "👎👎👎(NOT Statistically Significant) 👎👎👎"
      end
      io.puts
      io.puts "[#{newest.name}] #{newest.desc.inspect} - (#{newest.median} seconds)"
      io.puts "  #{change_direction} by:"
      io.puts "    #{align}#{FORMAT % x_faster}x [older/newer]"
      io.puts "    #{FORMAT % percent_faster}\% [(older - newer) / older * 100]"
      io.puts "[#{oldest.name}] #{oldest.desc.inspect} - (#{oldest.median} seconds)"
      io.puts
      io.puts "Iterations per sample: #{ENV["TEST_COUNT"]}"
      io.puts "Samples: #{newest.values.length}"
      io.puts
      io.puts "Test type: Kolmogorov Smirnov"
      io.puts "Confidence level: #{@stats[:confidence_level] * 100} %"
      io.puts "Is significant? (max > critical): #{significant?}"
      io.puts "D critical: #{d_critical}"
      io.puts "D max: #{d_max}"

      histogram(io)

      io.puts
    end
  end
end
