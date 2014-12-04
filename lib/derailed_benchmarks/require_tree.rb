# Tree structure used to store and sort require memory costs
# RequireTree.new('get_process_mem')
module DerailedBenchmarks
  class RequireTree
    attr_reader   :name
    attr_accessor :cost

    def initialize(name)
      @name     = name
      @children = {}
    end

    def <<(tree)
      @children[tree.name.to_s] = tree
    end

    def [](name)
      @children[name.to_s]
    end

    # Returns array of child nodes
    def children
      @children.values
    end

    def cost
      @cost || 0
    end

    # Returns sorted array of child nodes from Largest to Smallest
    def sorted_children
      children.sort { |c1, c2| c2.cost <=> c1.cost }
    end

    # Recursively prints all child nodes
    def print_sorted_children(level = 0, out = STDOUT)
      return if cost < ENV['CUT_OFF'].to_f
      out.puts "  " * level + "#{name}: #{cost.round(4)} mb"
      level += 1
      sorted_children.each do |child|
        child.print_sorted_children(level, out)
      end
    end
  end
end
