class DerailedBenchmarks < Rails::Railtie
  rake_tasks do
    load "tasks/perf.rake"
  end
end
