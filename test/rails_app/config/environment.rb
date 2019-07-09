# frozen_string_literal: true

# Load the rails application
require File.expand_path('../application', __FILE__)

# Initialize the rails application
Rails.application.config.active_record.sqlite3.represent_boolean_as_integer = true

Dummy::Application.initialize!
