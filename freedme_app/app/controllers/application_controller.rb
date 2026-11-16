class ApplicationController < ActionController::Base
  helper_method :current_account
  def current_account
    return nil unless Journeys::Support.enabled? && session[:expires_at].to_i > Time.current.to_i
    account = @current_account ||= Account.find_by(id: session[:account_id], status: "active")
    if Staff::Authentication.staff?(account)
      credential = StaffCredential.find_by(account_id: account.id)
      return nil unless credential&.mfa_enrolled_at && credential.session_version.present? && session[:staff_auth_version] == credential.session_version
    end
    account
  end
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern
end
