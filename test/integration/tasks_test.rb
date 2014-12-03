require 'test_helper'
require 'shellwords'

class TasksTest < ActiveSupport::TestCase

  def setup
    FileUtils.mkdir_p(dummy_path('tmp'))
  end

  def teardown
    FileUtils.remove_entry_secure(dummy_path('tmp'))
  end

  def rake(cmd, assert_success: true, env: {})
    env_string = env.map {|key, value| "#{key.shellescape}=#{value.to_s.shellescape}" }.join(" ")
    cmd        = "env #{env_string} rake -f perf.rake #{cmd} --trace"
    puts "Running: #{cmd}"
    result = `cd #{dummy_path} && #{cmd}`
    if assert_success
      assert $?.success?, "Expected #{cmd} to return a success status.\nOutput: #{result}"
    end

    result
  end

  test 'test' do
    rake "perf:test"
  end

  test 'TEST_COUNT' do
    result = rake "perf:test", env: { "TEST_COUNT" => 1 }
    assert_match "1 requests", result
  end

  test 'PATH_TO_HIT' do
    result = rake "perf:test", env: { "PATH_TO_HIT" => 'foo' }
    assert_match 'Endpoint: "foo"', result
  end

  test 'USE_SERVER' do
    result = rake "perf:test", env: { "USE_SERVER" => 'webrick', "TEST_COUNT" => 1 }
    assert_match 'Server: "webrick"', result
  end

  test '' do
  end

  test 'mem' do
    rake "perf:mem"
  end

  test 'require_bench' do
    rake "perf:require_bench"
  end

  test 'ram_over_time' do
    rake "perf:ram_over_time"
  end

  test 'ips' do
    rake "perf:ram_over_time"
  end
end
