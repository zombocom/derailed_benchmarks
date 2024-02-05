class UsersController < ApplicationController
  def create
    User.create!(user_params)

    head :created
  end

  private

  def user_params
    params.require(:user).permit(:email, :password, :password_confirmation)
  end
end