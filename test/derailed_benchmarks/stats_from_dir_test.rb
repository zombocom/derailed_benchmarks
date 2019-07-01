# frozen_string_literal: true

require 'test_helper'

class StatsFromDirTest < ActiveSupport::TestCase
  test "that it works" do
    dir = fixtures_dir("stats/significant")
    branch_info = {}
    branch_info["loser"]  = { desc: "Old commit", time: Time.now, file: dir.join("loser.bench.txt"), name: "loser" }
    branch_info["winner"] = { desc: "I am the new commit", time: Time.now + 1, file: dir.join("winner.bench.txt"), name: "winner" }
    stats = DerailedBenchmarks::StatsFromDir.new(branch_info)

    newest = stats.newest
    oldest = stats.oldest

    assert newest.average < oldest.average

    assert_equal "winner", newest.name
    assert_equal "loser", oldest.name

    assert 3.6e-05 < stats.p_value
    assert 3.8e-05 > stats.p_value
    assert_equal true, stats.significant?

    assert_equal "1.0062", stats.x_faster
    assert_equal "0.6131", stats.percent_faster
 end

  test "banner faster" do
    dir = fixtures_dir("stats/significant")
    branch_info = {}
    branch_info["loser"]  = { desc: "Old commit", time: Time.now, file: dir.join("loser.bench.txt"), name: "loser" }
    branch_info["winner"] = { desc: "I am the new commit", time: Time.now + 1, file: dir.join("winner.bench.txt"), name: "winner" }
    stats = DerailedBenchmarks::StatsFromDir.new(branch_info)
    newest = stats.newest
    oldest = stats.oldest

    # Test fixture for banner
    def stats.p_value
      "0.000037"
    end

    def newest.average
      10.5
    end

    def oldest.average
      11.0
    end

    expected = <<-EOM
[winner] "I am the new commit" - (10.5 seconds)
  FASTER by:
    1.0476x [older/newer]
    4.5455% [(older - newer) / older * 100]
[loser] "Old commit" - (11.0 seconds)

P-value: 0.000037
Is significant? (P-value < 0.05): true
EOM

    actual = StringIO.new
    stats.banner(actual)

    assert_match expected, actual.string
  end

  test "banner slower" do
    dir = fixtures_dir("stats/significant")
    branch_info = {}
    branch_info["loser"]  = { desc: "I am the new commit", time: Time.now, file: dir.join("loser.bench.txt"), name: "loser" }
    branch_info["winner"] = { desc: "Old commit", time: Time.now - 10, file: dir.join("winner.bench.txt"), name: "winner" }
    stats = DerailedBenchmarks::StatsFromDir.new(branch_info)
    newest = stats.newest
    oldest = stats.oldest

    def oldest.average
      10.5
    end

    def newest.average
      11.0
    end

    expected = <<-EOM
[loser] "I am the new commit" - (11.0 seconds)
  SLOWER by:
    0.9545x [older/newer]
    -4.7619% [(older - newer) / older * 100]
[winner] "Old commit" - (10.5 seconds)
EOM

    actual = StringIO.new
    stats.banner(actual)

    assert_match expected, actual.string
  end

  test "stats from samples with slightly different sizes" do
    stats = DerailedBenchmarks::StatsFromDir.new({})
    out = stats.students_t_test([100,101,102], [1,3])
    assert out[:alternative]
  end
end
