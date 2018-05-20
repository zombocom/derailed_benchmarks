require 'test_helper'
require 'shellwords'

class TasksTest < ActiveSupport::TestCase

  def setup
    FileUtils.mkdir_p(rails_app_path('tmp'))
  end

  def teardown
    FileUtils.remove_entry_secure(rails_app_path('tmp'))
  end

  def rake(cmd, options = {})
    assert_success = options[:assert_success] || true
    env             = options[:env]           || {}
    env_string = env.map {|key, value| "#{key.shellescape}=#{value.to_s.shellescape}" }.join(" ")
    cmd        = "env #{env_string} bundle exec rake -f perf.rake #{cmd} --trace"
    puts "Running: #{cmd}"
    result = `cd '#{rails_app_path}' && #{cmd}`
    if assert_success
      assert $?.success?, "Expected '#{cmd}' to return a success status.\nOutput: #{result}"
    end

    result
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

  test 'TEST_COUNT' do
    result = rake "perf:test", env: { "TEST_COUNT" => 1 }
    assert_match "1 requests", result
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
      "HTTP_AUTHORIZATION" => "Basic #{Base64.encode64("admin:secret")}",
      "HTTP_CACHE_CONTROL" => "no-cache"
    }
    result = rake "perf:test", env: env
    assert_match 'Endpoint: "foo_secret"', result
    assert_match 'HTTP headers: {"Authorization"=>"Basic YWRtaW46c2VjcmV0\n", "Cache-Control"=>"no-cache"}', result

    env["USE_SERVER"] = "webrick"
    result = rake "perf:test", env: env
    assert_match 'HTTP headers: {"Authorization"=>"Basic YWRtaW46c2VjcmV0\n", "Cache-Control"=>"no-cache"}', result
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
    rake "perf:mem_over_time"
  end
end
