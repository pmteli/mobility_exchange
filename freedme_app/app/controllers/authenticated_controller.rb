class AuthenticatedController < ApplicationController
  before_action :require_verified_session
  private
  def require_verified_session
    response.headers["Cache-Control"] = "no-store"
    unless Journeys::Support.enabled? && current_account
      session[:return_to] = request.path if request.get? && request.path.start_with?("/") && !request.path.start_with?("//")
      redirect_to sign_in_path, alert: "Sign in to continue. SMS and verification are simulated locally."
    end
  end
end
