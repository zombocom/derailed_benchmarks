# frozen_string_literal: true

namespace :perf do
  task :rails_load do
    ENV["RAILS_ENV"] ||= "production"
    ENV['RACK_ENV']  = ENV["RAILS_ENV"]
    ENV["DISABLE_SPRING"] = "true"

    ENV["SECRET_KEY_BASE"] ||= "foofoofoo"

    ENV['LOG_LEVEL'] ||= "FATAL"

    require 'rails'

    puts "Booting: #{Rails.env}"

    %W{ . lib test config }.each do |file|
      $LOAD_PATH << File.expand_path(file)
    end

    require 'application'

    Rails.env = ENV["RAILS_ENV"]

    DERAILED_APP = Rails.application

    # Disables CSRF protection because of non-GET requests
    DERAILED_APP.config.action_controller.allow_forgery_protection = false

    if DERAILED_APP.respond_to?(:initialized?)
      DERAILED_APP.initialize! unless DERAILED_APP.initialized?
    else
      DERAILED_APP.initialize! unless DERAILED_APP.instance_variable_get(:@initialized)
    end

    if !ENV["DERAILED_SKIP_ACTIVE_RECORD"] && defined? ActiveRecord
      if defined? ActiveRecord::Tasks::DatabaseTasks
        ActiveRecord::Tasks::DatabaseTasks.create_current
      else # Rails 3.2
        raise "No valid database for #{ENV['RAILS_ENV']}, please create one" unless ActiveRecord::Base.connection.active?.inspect
      end

      ActiveRecord::Migrator.migrations_paths = DERAILED_APP.paths['db/migrate'].to_a
      ActiveRecord::Migration.verbose         = true

      # https://github.com/plataformatec/devise/blob/master/test/orm/active_record.rb
      if Rails.version >= "7.1"
        ActiveRecord::MigrationContext.new(ActiveRecord::Migrator.migrations_paths).migrate
      elsif Rails.version >= "6.0"
        ActiveRecord::MigrationContext.new(ActiveRecord::Migrator.migrations_paths, ActiveRecord::SchemaMigration).migrate
      elsif Rails.version.start_with?("5.2")
        ActiveRecord::MigrationContext.new(ActiveRecord::Migrator.migrations_paths).migrate
      else
        ActiveRecord::Migrator.migrate(ActiveRecord::Migrator.migrations_paths, nil)
      end
    end

    DERAILED_APP.config.consider_all_requests_local = true
  end

  task :rack_load do
    puts "You're not using Rails"
    puts "You need to tell derailed how to boot your app"
    puts "In your perf.rake add:"
    puts
    puts "namespace :perf do"
    puts "  task :rack_load do"
    puts "    # DERAILED_APP = your code here"
    puts "  end"
    puts "end"
  end

  task :setup do
    if DerailedBenchmarks.gem_is_bundled?("railties")
      Rake::Task["perf:rails_load"].invoke
    else
      Rake::Task["perf:rack_load"].invoke
    end

    WARM_COUNT  = (ENV['WARM_COUNT'] || 0).to_i
    TEST_COUNT  = (ENV['TEST_COUNT'] || ENV['CNT'] || 1_000).to_i
    PATH_TO_HIT = ENV["PATH_TO_HIT"] || ENV['ENDPOINT'] || "/"
    REQUEST_METHOD = ENV["REQUEST_METHOD"] || "GET"
    REQUEST_BODY = ENV["REQUEST_BODY"]
    puts "Method: #{REQUEST_METHOD}"
    puts "Endpoint: #{ PATH_TO_HIT.inspect }"

    # See https://www.rubydoc.info/github/rack/rack/file/SPEC#The_Environment
    # All HTTP_ variables are accepted in the Rack environment hash, except HTTP_CONTENT_TYPE and HTTP_CONTENT_LENGTH.
    # For those, the HTTP_ prefix has to be removed.
    HTTP_HEADER_PREFIX = "HTTP_".freeze
    HTTP_HEADER_REGEXP = /^#{HTTP_HEADER_PREFIX}.+|CONTENT_(TYPE|LENGTH)$/
    RACK_ENV_HASH = ENV.select { |key| key =~ HTTP_HEADER_REGEXP }

    HTTP_HEADERS = RACK_ENV_HASH.keys.inject({}) do |hash, rack_header_name|
      # e.g. "HTTP_ACCEPT_CHARSET" -> "Accept-Charset"
      upper_case_header_name =
        if rack_header_name.start_with?(HTTP_HEADER_PREFIX)
          rack_header_name[HTTP_HEADER_PREFIX.size..-1]
        else
          rack_header_name
        end

      header_name = upper_case_header_name.split("_").map(&:downcase).map(&:capitalize).join("-")

      hash[header_name] = RACK_ENV_HASH[rack_header_name]
      hash
    end
    puts "HTTP headers: #{HTTP_HEADERS}" unless HTTP_HEADERS.empty?

    CURL_HTTP_HEADER_ARGS = HTTP_HEADERS.map { |http_header_name, value| "-H \"#{http_header_name}: #{value}\"" }.join(" ")
    CURL_BODY_ARG = REQUEST_BODY ? "-d '#{REQUEST_BODY}'" : nil

    if REQUEST_METHOD != "GET" && REQUEST_BODY
      RACK_ENV_HASH["GATEWAY_INTERFACE"] = "CGI/1.1"
      RACK_ENV_HASH[:input] = REQUEST_BODY.dup
      puts "Body: #{REQUEST_BODY}"
    end

    require 'rack/test'

    DERAILED_APP = DerailedBenchmarks.add_auth(Object.class_eval { remove_const(:DERAILED_APP) })
    if server = ENV["USE_SERVER"]
      @port = (3000..3900).to_a.sample
      puts "Port: #{ @port.inspect }"
      puts "Server: #{ server.inspect }"
      thread = Thread.new do
        # rack 3 doesn't have Rack::Server
        require 'rackup' unless defined?(Rack::Server)
        server_class = defined?(Rack::Server) ? Rack::Server : Rackup::Server
        server_class.start(app: DERAILED_APP, :Port => @port, environment: "none", server: server)
      end
      sleep 1

      def call_app(path = File.join("/", PATH_TO_HIT))
        cmd = "curl -X #{REQUEST_METHOD} #{CURL_HTTP_HEADER_ARGS} #{CURL_BODY_ARG} -s --fail 'http://localhost:#{@port}#{path}' 2>&1"
        response = `#{cmd}`
        unless $?.success?
          STDERR.puts "Couldn't call app."
          STDERR.puts "Bad request to #{cmd.inspect} \n\n***RESPONSE***:\n\n#{ response.inspect }"

          FileUtils.mkdir_p("tmp")
          File.open("tmp/fail.html", "w+") {|f| f.write response }

          `open #{File.expand_path("tmp/fail.html")}` if ENV["DERAILED_DEBUG"]

          exit(1)
        end
      end
    else
      @app = Rack::MockRequest.new(DERAILED_APP)

      def call_app
        response = @app.request(REQUEST_METHOD, PATH_TO_HIT, RACK_ENV_HASH)
        if response.status != 200
          STDERR.puts "Couldn't call app. Bad request to #{PATH_TO_HIT}! Resulted in #{response.status} status."
          STDERR.puts "\n\n***RESPONSE BODY***\n\n"
          STDERR.puts response.body

          FileUtils.mkdir_p("tmp")
          File.open("tmp/fail.html", "w+") {|f| f.write response.body }

          `open #{File.expand_path("tmp/fail.html")}` if ENV["DERAILED_DEBUG"]

          exit(1)
        end
        response
      end
    end
    if WARM_COUNT > 0
      puts "Warming up app: #{WARM_COUNT} times"
      WARM_COUNT.times { call_app }
    end
  end
end
