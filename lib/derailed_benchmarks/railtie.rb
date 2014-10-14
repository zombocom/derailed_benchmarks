module DerailedBenchmarks
  class Railtie < Rails::Railtie
    rake_tasks do
      load "derailed_benchmarks/tasks"
    end
  end
end