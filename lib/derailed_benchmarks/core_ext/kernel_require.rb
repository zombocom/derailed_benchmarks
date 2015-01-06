require 'get_process_mem'
require 'derailed_benchmarks/require_tree'

# This file contains classes and monkey patches to measure the amount of memory
# useage requiring an individual file adds.

# Monkey patch kernel to ensure that all `require` calls call the same
# method
module Kernel
  alias :original_require :require
  REQUIRE_STACK = []

  def require(file)
    Kernel.require(file)
  end

  # This breaks things, not sure how to fix
  # def require_relative(file)
  #   Kernel.require_relative(file)
  # end
  class << self
    alias :original_require          :require
    # alias :original_require_relative :require_relative
  end

  # The core extension we use to measure require time of all requires
  # When a file is required we create a tree node with its file name.
  # We then push it onto a stack, this is because requireing a file can
  # require other files before it is finished.
  #
  # When a child file is required, a tree node is created and the child file
  # is pushed onto the parents tree. We then repeat the process as child
  # files may require aditional files.
  #
  # When a require returns we remove it from the require stack so we don't
  # accidentally push additional children nodes to it. We then store the
  # memory cost of the require in the tree node.
  def self.measure_memory_impact(file, &block)
    mem    = GetProcessMem.new
    node   = DerailedBenchmarks::RequireTree.new(file)

    parent = REQUIRE_STACK.last
    parent << node
    REQUIRE_STACK.push(node)
    begin
      before = mem.mb
      block.call file
    ensure
      REQUIRE_STACK.pop # node
      after = mem.mb
    end
    node.cost = after - before
  end
end

# Top level node that will store all require information for the entire app
TOP_REQUIRE = DerailedBenchmarks::RequireTree.new("TOP")
REQUIRE_STACK.push(TOP_REQUIRE)

Kernel.define_singleton_method(:require) do |file|
  measure_memory_impact(file) { |file| original_require(file) }
end

# Kernel.define_singleton_method(:require_relative) do |file|
#   measure_memory_impact(file) { |file| original_require_relative(file) }
# end
