# frozen_string_literal: true

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
      @stats = students_t_test
      self
    end

    def students_t_test(series_1=oldest.values, series_2=newest.values)
      StatisticalTest::TTest.perform(
        alpha = 0.05,
        :two_tail,
        series_1,
        series_2
      )
    end

    def significant?
      @stats[:alternative]
    end

    def p_value
      @stats[:p_value].to_f
    end

    def x_faster
      FORMAT % (oldest.average/newest.average).to_f
    end

    def percent_faster
      FORMAT % (((oldest.average - newest.average) / oldest.average).to_f  * 100)
    end

    def change_direction
      newest.average < oldest.average ? "FASTER" : "SLOWER"
    end

    def banner(io = Kernel)
      io.puts
      if significant?
        io.puts "❤️ ❤️ ❤️  (Statistically Significant) ❤️ ❤️ ❤️"
      else
        io.puts "👎👎👎(NOT Statistically Significant) 👎👎👎"
      end
      io.puts
      io.puts "[#{newest.name}] #{newest.desc.inspect} - (#{newest.average} seconds)"
      io.puts "  #{change_direction} by:"
      io.puts "    #{x_faster}x [older/newer]"
      io.puts "    #{percent_faster}\% [(older - newer) / older * 100]"
      io.puts "[#{oldest.name}] #{oldest.desc.inspect} - (#{oldest.average} seconds)"
      io.puts
      io.puts "Iterations per sample: #{ENV["TEST_COUNT"]}"
      io.puts "Samples: #{newest.values.length}"
      io.puts "P-value: #{p_value}"
      io.puts "Is significant? (P-value < 0.05): #{significant?}"
      io.puts
    end
  end
end
