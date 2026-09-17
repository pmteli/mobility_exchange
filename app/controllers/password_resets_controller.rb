class PasswordResetsController < ApplicationController
  rate_limit to: 5, within: 1.hour, only: :create
  def new; end
  def create
    MobilityTransaction.call do
      user = User.find_by("lower(email) = ?", params[:email].to_s.strip.downcase)
      if user&.credential && user.email_verified_at && user.account_status == "active"
        Notification.create!(deduplication_key: "reset:#{SecureRandom.uuid}", recipient_user_id: user.id, channel: "email", destination: user.email, template_key: "reset", payload_json: { token: AccountTokens.issue(user, "reset") })
      end
    end
    redirect_to new_session_path, notice: "If an eligible account exists, a reset link will be emailed."
  end
  def edit
    @token = params[:token]
    raise ActiveRecord::RecordNotFound unless AccountTokens.resolve(@token, "reset")
  end
  def update
    @token = params[:token]
    MobilityTransaction.call do
      user = AccountTokens.resolve(params[:token], "reset") or raise ActiveRecord::RecordNotFound
      user.credential.update!(password: params[:password], password_confirmation: params[:password_confirmation], token_nonce: SecureRandom.hex(32))
      LoginSession.where(user_id: user.id).delete_all
    end
    reset_session
    redirect_to new_session_path, notice: "Password changed. Sign in again."
  rescue ActiveRecord::RecordInvalid => error
    @password_errors = error.record.errors.full_messages
    render :edit, status: :unprocessable_entity
  end
end
