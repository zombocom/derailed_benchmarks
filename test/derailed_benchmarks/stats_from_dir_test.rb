require 'test_helper'

class StatsFromDirTest < ActiveSupport::TestCase
  test "default_cost" do
    dir = fixtures_dir("stats/significant")
    stats = DerailedBenchmarks::StatsFromDir.new(dir)

    fastest = stats.fastest
    slowest = stats.slowest

    assert fastest.average < slowest.average

    assert_equal "winner", fastest.name
    assert_equal "loser", slowest.name

    assert_equal "1.0062", stats.x_faster
    assert_equal "0.6131", stats.percent_faster

    assert_equal 3.733653842080382e-05, stats.p_value
    assert_equal true, stats.significant?

    expected = <<-EOM
Test "winner" is faster than "loser" by
  1.0062x faster or 0.6131% faster

P-value: 3.733653842080382e-05
Is signifigant? (P-value < 0.05): true
EOM

    actual = StringIO.new
    actual.flush
    stats.banner(actual)

    assert_match expected, actual.string
  end
end
