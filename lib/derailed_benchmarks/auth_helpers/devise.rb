module DerailedBenchmarks
  class AuthHelpers
    # Devise helper for authenticating requests
    # Setup adds necessarry test methods, user provides a sample user.
    # The authenticate method is called on every request when authentication is enabled
    class Devise < AuthHelper
      attr_accessor :user

      # Include devise test helpers and turn on test mode
      # We need to do this on the class level
      def setup
        # self.class.instance_eval do
          require 'devise'
          require 'warden'
          extend ::Warden::Test::Helpers
          extend ::Devise::TestHelpers
          Warden.test_mode!
        # end
      end

      def user
        @user ||= begin
          password = SecureRandom.hex
          User.first_or_create!(email: "#{SecureRandom.hex}@example.com", password: password, password_confirmation: password)
        end
      end

      # Logs the user in, then call the parent app
      def call(env)
        login_as(user)
        app.call(env)
      end
    end
  end
end

