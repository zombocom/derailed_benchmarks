# frozen_string_literal: true

require 'test_helper'
require 'shellwords'

class TasksTest < ActiveSupport::TestCase

  def setup
    FileUtils.mkdir_p(rails_app_path('tmp'))
  end

  def teardown
    FileUtils.remove_entry_secure(rails_app_path('tmp'))
  end

  def run!(cmd)
    out = `#{cmd}`
    raise "Could not run #{cmd}, output: #{out}" unless $?.success?
    out
  end

  def rake(cmd, options = {})
    assert_success = options.key?(:assert_success) ? options[:assert_success] : true
    env             = options[:env]           || {}
    env_string = env.map {|key, value| "#{key.shellescape}=#{value.to_s.shellescape}" }.join(" ")
    cmd        = "env #{env_string} bundle exec rake -f perf.rake #{cmd} --trace"
    result = Bundler.with_original_env do
      # Ensure relative BUNDLE_GEMFILE is expanded so path is still correct after cd
      ENV['BUNDLE_GEMFILE'] = File.expand_path(ENV['BUNDLE_GEMFILE']) if ENV['BUNDLE_GEMFILE']
      `cd '#{rails_app_path}' && #{cmd} 2>&1` 
    end
    if assert_success && !$?.success?
      puts result
      raise "Expected '#{cmd}' to return a success status.\nOutput: #{result}"
    end

    result
  end

  test 'non-rails library with branch specified' do
    skip unless ENV['USING_RAILS_WICKED_BRANCH']

    gem_path = run!("bundle info wicked --path")
    env = { "TEST_COUNT" => 10, "DERAILED_SCRIPT_COUNT" => 2, "DERAILED_PATH_TO_LIBRARY" => gem_path}
    puts rake "perf:library", { env: env }
  end

  test 'rails perf:library from git' do
    # BUNDLE_GEMFILE="gemfiles/rails_git.gemfile" bundle exec m test/integration/tasks_test.rb:<linenumber>

    skip # unless ENV['USING_RAILS_GIT']

    env = { "TEST_COUNT" => 2, "DERAILED_SCRIPT_COUNT" => 2,
            "SHAS_TO_TEST" => "fd9308a2925e862435859e1803e720e6eebe4bb6,aa85e897312396b5c6993d8092b9aff7faa93011"}
    puts rake "perf:library", { env: env }
  end

  test "rails perf:library with bad script" do
    # BUNDLE_GEMFILE="gemfiles/rails_git.gemfile" bundle exec m test/integration/tasks_test.rb:<linenumber>

    skip # unless ENV['USING_RAILS_GIT']

    error = assert_raises {
      env = { "DERAILED_SCRIPT" => "nopenopenop", "TEST_COUNT" => 2, "DERAILED_SCRIPT_COUNT" => 2,
              "SHAS_TO_TEST" => "fd9308a2925e862435859e1803e720e6eebe4bb6,aa85e897312396b5c6993d8092b9aff7faa93011"}
      puts rake "perf:library", { env: env }
    }

    assert error.message =~ /nopenopenop:( command)? not found/, "Expected #{error.message} to include /nopenopenop: (command)? not found/ but it did not"
  end

  test 'hitting authenticated devise apps' do
    env = { "PATH_TO_HIT" => "authenticated", "USE_AUTH" => "true", "TEST_COUNT" => "2" }
    result = rake 'perf:test', env: env
    assert_match 'Auth: true', result

    env["USE_SERVER"] = "webrick"
    result = rake 'perf:test', env: env
    assert_match 'Auth: true',        result
    assert_match 'Server: "webrick"', result
  end

  test 'authenticate with a custom user' do
    env = { "AUTH_CUSTOM_USER" => "true", "PATH_TO_HIT" => "authenticated", "USE_AUTH" => "true", "TEST_COUNT" => "2" }
    result = rake 'perf:test', env: env
    assert_match 'Auth: true', result
  end

  test 'test' do
    rake "perf:test"
  end

  test 'app' do
    skip unless ENV['USING_RAILS_GIT']
    run!("cd #{rails_app_path} && git init . && git add . && git commit -m first && git commit --allow-empty -m second")
    env = { "TEST_COUNT" => 10, "DERAILED_SCRIPT_COUNT" => 2 }
    puts rake "perf:app", { env: env }
  end

  test 'TEST_COUNT' do
    result = rake "perf:test", env: { "TEST_COUNT" => 1 }
    assert_match "1 derailed requests", result
  end

  test 'WARM_COUNT' do
    result = rake "perf:test", env: { "WARM_COUNT" => 1 }
    assert_match "Warming up app:", result
  end

  test 'PATH_TO_HIT' do
    env    = { "PATH_TO_HIT" => 'foo', "TEST_COUNT" => "2" }
    result = rake "perf:test", env: env
    assert_match 'Endpoint: "foo"', result

    env["USE_SERVER"] = "webrick"
    result = rake "perf:test", env: env
    assert_match 'Endpoint: "foo"',   result
    assert_match 'Server: "webrick"', result
  end

  test 'HTTP headers' do
    env = {
      "PATH_TO_HIT" => 'foo_secret',
      "TEST_COUNT" => "2",
      "HTTP_AUTHORIZATION" => "Basic #{Base64.strict_encode64("admin:secret")}",
      "HTTP_CACHE_CONTROL" => "no-cache"
    }
    result = rake "perf:test", env: env
    assert_match 'Endpoint: "foo_secret"', result
    assert_match (/"Authorization"=>"Basic YWRtaW46c2VjcmV0"/), result
    assert_match (/"Cache-Control"=>"no-cache"/), result

    env["USE_SERVER"] = "webrick"
    result = rake "perf:test", env: env
    assert_match (/"Authorization"=>"Basic YWRtaW46c2VjcmV0"/), result
    assert_match (/"Cache-Control"=>"no-cache"/), result
  end

  test 'CONTENT_TYPE' do
    env = {
      "REQUEST_METHOD" => "POST",
      "PATH_TO_HIT" => "users",
      "CONTENT_TYPE" => "application/json",
      "REQUEST_BODY" => '{"user":{"email":"foo@bar.com","password":"123456","password_confirmation":"123456"}}',
      "TEST_COUNT" => "2"
    }

    result = rake "perf:test", env: env
    assert_match 'Body: {"user":{"email":"foo@bar.com","password":"123456","password_confirmation":"123456"}}', result
    assert_match 'HTTP headers: {"Content-Type"=>"application/json"}', result

    env["USE_SERVER"] = "webrick"
    result = rake "perf:test", env: env
    assert_match 'Body: {"user":{"email":"foo@bar.com","password":"123456","password_confirmation":"123456"}}', result
    assert_match 'HTTP headers: {"Content-Type"=>"application/json"}', result
  end

  test 'REQUEST_METHOD and REQUEST_BODY' do
    env = {
      "REQUEST_METHOD" => "POST",
      "PATH_TO_HIT" => "users",
      "REQUEST_BODY" => "user%5Bemail%5D=foo%40bar.com&user%5Bpassword%5D=123456&user%5Bpassword_confirmation%5D=123456",
      "TEST_COUNT" => "2"
    }

    result = rake "perf:test", env: env
    assert_match 'Endpoint: "users"', result
    assert_match 'Method: POST', result
    assert_match 'Body: user%5Bemail%5D=foo%40bar.com&user%5Bpassword%5D=123456&user%5Bpassword_confirmation%5D=123456', result

    env["USE_SERVER"] = "webrick"
    result = rake "perf:test", env: env
    assert_match 'Method: POST', result
    assert_match 'Body: user%5Bemail%5D=foo%40bar.com&user%5Bpassword%5D=123456&user%5Bpassword_confirmation%5D=123456', result
  end

  test 'USE_SERVER' do
    result = rake "perf:test", env: { "USE_SERVER" => 'webrick', "TEST_COUNT" => "2" }
    assert_match 'Server: "webrick"', result
  end

  test '' do
  end

  test 'objects' do
    rake "perf:objects"
  end

  test 'mem' do
    rake "perf:mem"
  end

  test 'mem_over_time' do
    rake "perf:mem_over_time"
  end

  test 'ips' do
    rake "perf:ips"
  end

  test 'heap_diff' do
    rake "perf:heap_diff", env: { "TEST_COUNT" => 5 }
  end
end
