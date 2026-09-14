class VerificationRequestsController < ApplicationController
  rate_limit to: 5, within: 1.hour, only: :create
  def new; end
  def create
    Workflow.run do
      user = User.find_by("lower(email) = ?", params[:email].to_s.strip.downcase)
      if user&.credential && user.account_status == "pending"
        Notification.create!(deduplication_key: "verify:#{SecureRandom.uuid}", recipient_user_id: user.id, channel: "email", destination: user.email, template_key: "verification", payload_json: { token: AccountTokens.issue(user, "verify") })
      end
    end
    redirect_to new_session_path, notice: "If an unverified account exists, a new verification link will be emailed."
  end
end
