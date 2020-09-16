# frozen_string_literal: true

require 'test_helper'

class KernelRequireTest < ActiveSupport::TestCase
  setup do
    require 'derailed_benchmarks/core_ext/kernel_require'
    GC.disable
  end

  teardown do
    GC.enable
  end

  def assert_node_in_parent(file_name, parent)
    file = fixtures_dir(File.join("require", file_name))
    node = parent[file]
    assert node,                    "Expected:\n#{parent.children}\nto include:\n#{file.inspect}"
    assert node.cost < parent.cost, "Expected:\n#{node.inspect}\nto cost less than:\n#{parent.inspect}" unless parent == TOP_REQUIRE
    node
  end

  test "profiles autoload" do
    require fixtures_dir("require/autoload_parent.rb")
    parent = assert_node_in_parent("autoload_parent.rb", TOP_REQUIRE)

    assert_node_in_parent("autoload_child.rb", parent)
  end

  test "core extension profiles useage" do
    require fixtures_dir("require/parent_one.rb")
    parent    = assert_node_in_parent("parent_one.rb", TOP_REQUIRE)
    assert_node_in_parent("child_one.rb", parent)
    child_two = assert_node_in_parent("child_two.rb", parent)
    assert_node_in_parent("relative_child", parent)
    assert_node_in_parent("relative_child_two", parent)
    assert_node_in_parent("raise_child.rb", child_two)
  end
end
