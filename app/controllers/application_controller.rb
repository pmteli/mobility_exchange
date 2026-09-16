class ApplicationController < ActionController::Base
  before_action { response.headers["Cache-Control"] = "private, no-store" }
  helper_method :current_user, :allowed?
  rescue_from ActiveRecord::RecordNotFound, with: -> { render plain: "Record not found", status: :not_found }
  rescue_from ActiveRecord::RecordInvalid, with: :invalid_record
  rescue_from ActiveRecord::RecordNotUnique, with: -> { render plain: "That record already exists. Go back and try again.", status: :unprocessable_entity }
  rescue_from Workflow::Error, with: ->(error) { render plain: error.message, status: :unprocessable_entity }
  private
  def current_user
    return @current_user if defined?(@current_user)
    login = LoginSession.where("expires_at > ?", Time.current).find_by(id: session[:login_id])
    @current_user = login&.user
    @current_user = nil unless @current_user&.account_status == "active" && @current_user&.email_verified_at
    @current_user
  end
  def require_login
    redirect_to new_session_path, alert: "Sign in to continue." unless current_user
  end
  def allowed?(permission)
    current_user&.allowed?(permission) || false
  end
  def authorize!(permission)
    head :forbidden unless allowed?(permission)
  end
  def invalid_record(error)
    render plain: error.record.errors.full_messages.join(". "), status: :unprocessable_entity
  end
end
