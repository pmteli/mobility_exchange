class GoogleSessionsController < ApplicationController
  before_action :require_google_configuration
  before_action :load_pending_identity, only: [:new, :create]
  rate_limit to: 20, within: 5.minutes, only: [:start, :callback, :create], with: -> { redirect_to new_session_path, alert: "Too many sign-in attempts. Please wait five minutes." }

  def start
    session.delete(:google_pending)
    flow = { "state" => SecureRandom.hex(32), "nonce" => SecureRandom.hex(32),
      "verifier" => SecureRandom.urlsafe_base64(48), "expires_at" => 10.minutes.from_now.to_i }
    session[:google_flow] = flow
    redirect_to GoogleOauth.authorization_url(state: flow["state"], nonce: flow["nonce"], verifier: flow["verifier"]), allow_other_host: true
  end

  def callback
    response.set_header("Referrer-Policy", "no-referrer")
    flow = session.delete(:google_flow)
    unless flow && flow["expires_at"].to_i > Time.current.to_i && params[:state].is_a?(String) &&
        ActiveSupport::SecurityUtils.secure_compare(flow["state"], params[:state]) && params[:error].blank? && params[:code].present?
      raise GoogleOauth::Invalid
    end
    identity = GoogleOauth.identity(code: params[:code], verifier: flow["verifier"], nonce: flow["nonce"])
    login = GoogleAccount.login(identity)
    reset_session
    if login
      session[:login_id] = login.id
      redirect_to account_path, notice: "Signed in with Google."
    else
      session[:google_pending] = identity.merge("expires_at" => 10.minutes.from_now.to_i)
      redirect_to new_google_registration_path
    end
  rescue GoogleOauth::Invalid, Workflow::Error
    session.delete(:google_pending)
    redirect_to new_session_path, alert: "Google sign-in was cancelled, expired, or could not be verified. Please try again or sign in with your email and password."
  end

  def new; end

  def create
    login = GoogleAccount.complete(@identity, params.permit(:first_name, :last_name, :password, community_roles: []).to_h.symbolize_keys)
    reset_session
    session[:login_id] = login.id
    redirect_to account_path, notice: "Welcome! Your Google account is connected."
  rescue Workflow::Error, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => error
    @errors = error.is_a?(ActiveRecord::RecordInvalid) ? error.record.errors.full_messages :
      [error.is_a?(ActiveRecord::RecordNotUnique) ? "This account was just registered. Please sign in again." : error.message]
    render :new, status: :unprocessable_entity
  end

  private
  def require_google_configuration
    redirect_to new_session_path, alert: "Google sign-in is not available yet. Please use email and password." unless GoogleOauth.enabled?
  end

  def load_pending_identity
    @identity = session[:google_pending]
    unless @identity && @identity["expires_at"].to_i > Time.current.to_i
      session.delete(:google_pending)
      redirect_to new_session_path, alert: "Your Google sign-in expired. Please start again."
      return
    end
    @existing = User.exists?(["lower(email) = ?", @identity.fetch("email")])
  end
end
