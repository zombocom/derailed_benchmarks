class ApplicationController < ActionController::Base
  protect_from_forgery
  before_filter :pull_out_locale


  def pull_out_locale
    I18n.locale = params[:locale] if params[:locale].present?
  end
end
