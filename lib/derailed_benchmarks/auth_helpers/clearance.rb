# frozen_string_literal: true

module DerailedBenchmarks
  class AuthHelpers
    # Clearance helper for authenticating requests
    # Setup adds necessarry test methods, user provides a sample user.
    # The authenticate method is called on every request when authentication is enabled
    class Clearance < AuthHelper
      attr_writer :user

      # Include devise test helpers and turn on test mode
      # We need to do this on the class level
      def setup
        require "clearance/session"
      end

      def user
        if @user
          @user = @user.call if @user.is_a?(Proc)
          @user
        else
          password = SecureRandom.hex
          @user = User.first_or_create!(email: "#{SecureRandom.hex}@example.com", password: password)
        end
      end

      # Logs the user in, then call the parent app
      def call(env)
        session = Clearance::Session.new(env)
        env[:clearance] = session
        env[:clearance].sign_in(@user)
        session.add_cookie_to_headers
        app.call(env)
      end
    end
  end
end
