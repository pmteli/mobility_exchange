class SessionsController < ApplicationController
  before_action :local_only
  def new; end
  def create
    pending = Journeys::Authentication.start!(mobile: params[:mobile])
    session[:pending_login] = pending
    redirect_to verify_sign_in_path
  rescue Journeys::Authentication::RegistrationRequired => error
    session[:registration_mobile] = params[:mobile].to_s
    session.delete(:pending_login)
    redirect_to register_path, alert: error.message
  rescue Journeys::Error => error
    flash.now[:alert] = error.message
    render :new, status: :unprocessable_entity
  end
  def registration
    @mobile = session[:registration_mobile]
  end
  def register
    session[:pending_login] = Journeys::Authentication.start!(mobile: params[:mobile], name: params[:display_name], locality: params[:locality], registration: true)
    session.delete(:registration_mobile)
    redirect_to verify_sign_in_path
  rescue Journeys::Error => error
    @mobile = params[:mobile]
    flash.now[:alert] = error.message
    render :registration, status: :unprocessable_entity
  end
  def challenge
    redirect_to sign_in_path unless session[:pending_login]
  end
  def verify
    account = Journeys::Authentication.verify!(session[:pending_login], params[:code].to_s)
    destination = session[:return_to]
    reset_session
    session[:account_id] = account.id
    session[:expires_at] = 8.hours.from_now.to_i
    redirect_to(destination.presence || activity_path)
  rescue Journeys::Error, ActiveRecord::RecordNotFound => error
    flash.now[:alert] = error.message
    render :challenge, status: :unprocessable_entity
  end
  def destroy
    reset_session
    redirect_to root_path, notice: "Signed out."
  end
  private
  def local_only
    head :service_unavailable unless Journeys::Support.enabled?
  end
end
