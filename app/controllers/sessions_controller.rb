class SessionsController < ApplicationController
  rate_limit to: 10, within: 5.minutes, only: :create
  def new; end
  def create
    login = Authentication.login(email: params[:email], password: params[:password])
    reset_session
    session[:login_id] = login.id
    redirect_to account_path, notice: "Welcome back."
  rescue Authentication::Invalid
    flash.now[:alert] = "Sign in failed. Check your email, password, and verification status."
    render :new, status: :unprocessable_entity
  end
  def destroy
    MobilityTransaction.call { LoginSession.where(id: session[:login_id]).delete_all }
    reset_session
    redirect_to root_path, notice: "Signed out."
  end
end
