# frozen_string_literal: true

module DerailedBenchmarks
  # A class for reading in benchmark results
  # and converting them to numbers for comparison
  #
  # Example:
  #
  #  puts `cat muhfile.bench.txt`
  #
  #    9.590142   0.831269  10.457801 ( 10.0)
  #    9.836019   0.837319  10.728024 ( 11.0)
  #
  #  x = StatsForFile.new(name: "muhcommit", file: "muhfile.bench.txt", desc: "I made it faster", time: Time.now)
  #  x.values  #=> [11.437769, 11.792425]
  #  x.average # => 10.5
  #  x.name    # => "muhfile"
  class StatsForFile
    attr_reader :name, :values, :desc, :time

    def initialize(file:, name:, desc:, time: )
      @name = name
      @file = Pathname.new(file)
      @desc = desc
      @time = time
      @values = []
      load_file!

      @average = values.inject(:+) / values.length
    end

    def average
      @average.to_f
    end

    def load_file!
      @file.each_line do |line|
        line.match(/\( +(\d+\.\d+)\)/)
        begin
          values << BigDecimal($1)
        rescue => e
          raise e, "Problem with file #{file_name.inspect}:\n#{file_contents}\n#{e.message}"
        end
      end
      values.freeze
    end
  end
end
