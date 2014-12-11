class AuthenticatedController < ApplicationController
  if respond_to?(:before_filter)
    class << self
      alias :before_action :before_filter
    end
  end

  before_action :authenticate_user!

  def index
  end
end
