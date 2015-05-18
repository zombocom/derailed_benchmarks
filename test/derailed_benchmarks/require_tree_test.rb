require 'test_helper'

class RequireTree < ActiveSupport::TestCase

  def tree(name)
    DerailedBenchmarks::RequireTree.new(name)
  end

  test "default_cost" do
    parent =  tree("parent")
    assert_equal 0,       parent.cost
    value       = rand(0..100)
    parent.cost = value

    assert_equal value, parent.cost
  end

  test "stores child" do
    parent =  tree("parent")
    child  =  tree("child")
    parent << child

    # [](name)
    assert_equal child,   parent["child"]
    # children
    assert_equal [child], parent.children
    assert_equal [child], parent.sorted_children
  end

  test "sorts children" do
    parent = tree("parent")
    parent.cost = rand(5..10)
    small  = tree("small")
    small.cost = rand(10..100)

    large  = tree("large")
    large.cost = small.cost + 1

    parent << small
    parent << large

    expected = [large, small]
    assert_equal expected, parent.sorted_children

    expected = <<-OUT
parent: #{ parent.cost.round(4) } mb
  large: #{ large.cost.round(4) } mb
  small: #{ small.cost.round(4) } mb
OUT
    capture  = StringIO.new
    parent.print_sorted_children(0, capture)
    assert_equal expected, capture.string
  end
end
