class StaffSessionsController < ApplicationController
  before_action { response.headers['Cache-Control'] = 'no-store' }
  rate_limit to: 20, within: 5.minutes, only: [:create, :verify]
  def new; end
  def create
    credential = Staff::Authentication.password!(params[:identifier], params[:password])
    destination = session[:return_to]
    reset_session
    session[:return_to] = destination
    session[:staff_pending] = { 'id' => credential.account_id, 'version' => credential.session_version, 'until' => 5.minutes.from_now.to_i }
    redirect_to staff_verify_path
  rescue Staff::Authentication::Error => e
    flash.now[:alert] = e.message
    render :new, status: :unprocessable_entity
  end
  def challenge
    @credential = pending_credential
    redirect_to staff_sign_in_path, alert: 'Sign in again to continue.' unless @credential
  end
  def verify
    @credential = pending_credential
    unless @credential
      redirect_to staff_sign_in_path, alert: 'Sign in again to continue.'
      return
    end
    account = Staff::Authentication.verify!(@credential, params[:code])
    destination = session[:return_to]
    reset_session
    session[:account_id] = account.id
    session[:staff_auth_version] = @credential.session_version
    session[:expires_at] = 8.hours.from_now.to_i
    redirect_to(destination.to_s.start_with?('/') && !destination.to_s.start_with?('//') ? destination : activity_path)
  rescue Staff::Authentication::Error => e
    flash.now[:alert] = e.message
    render :challenge, status: :unprocessable_entity
  end
  private
  def pending_credential
    pending = session[:staff_pending]
    return unless pending && pending['until'].to_i > Time.current.to_i
    credential = StaffCredential.find_by(account_id: pending['id'], session_version: pending['version'])
    return unless credential && Staff::Authentication.staff?(credential.account)
    credential
  end
end
