class ApplicationController < ActionController::Base
  helper_method :current_account
  def current_account
    return nil unless Journeys::Support.enabled? && session[:expires_at].to_i > Time.current.to_i
    @current_account ||= Account.find_by(id: session[:account_id], status: "active")
  end
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern
end
