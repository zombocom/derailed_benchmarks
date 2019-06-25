# frozen_string_literal: true

require 'test_helper'

class DerailedBenchmarksTest < ActiveSupport::TestCase
  test "truth" do
    assert_kind_of Module, DerailedBenchmarks
  end

  test "gem_is_bundled?" do
    assert DerailedBenchmarks.gem_is_bundled?("rack")
    refute DerailedBenchmarks.gem_is_bundled?("wicked")
  end
end
