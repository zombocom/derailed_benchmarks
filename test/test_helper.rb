require 'rubygems'
require 'bundler/setup'

# Configure Rails Envinronment
ENV["RAILS_ENV"] = "test"

require 'rails'
require 'rails/test_help'

require 'stringio'
require 'pathname'

require 'derailed_benchmarks'

require File.expand_path("../rails_app/config/environment.rb",  __FILE__)
require "rails/test_help"

ActionMailer::Base.delivery_method    = :test
ActionMailer::Base.perform_deliveries = true
ActionMailer::Base.default_url_options[:host] = "test.com"

Rails.backtrace_cleaner.remove_silencers!

# Configure capybara for integration testing
require "capybara/rails"
Capybara.default_driver   = :rack_test
Capybara.default_selector = :css

require_relative "rails_app/config/environment"
ActiveRecord::Migrator.migrations_paths = [File.expand_path("../rails_app/db/migrate", __dir__)]

# Load support files
Dir["#{File.dirname(__FILE__)}/support/**/*.rb"].each { |f| require f }

class ActiveSupport::IntegrationCase
  def assert_has_content?(content)
    assert has_content?(content), "Expected #{page.body} to include #{content.inspect}"
  end
end


def fixtures_dir(name = "")
  root_path("test/fixtures").join(name)
end

def root_path(name = "")
  Pathname.new(File.expand_path("../..", __FILE__)).join(name)
end

def rails_app_path(name = "")
  root_path("test/rails_app").join(name)
end
