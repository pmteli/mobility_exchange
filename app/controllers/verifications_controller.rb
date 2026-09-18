class VerificationsController < ApplicationController
  def show
    @token = params[:token]
    raise ActiveRecord::RecordNotFound unless AccountTokens.resolve(@token, "verify")
  end
  def update
    MobilityTransaction.call do
      user = AccountTokens.resolve(params[:token], "verify") or raise ActiveRecord::RecordNotFound
      raise Workflow::Error, "Account cannot be verified." unless user.account_status == "pending"
      user.update!(email_verified_at: Time.current, account_status: "active")
      user.credential.update!(token_nonce: SecureRandom.hex(32))
      (user.community_roles & %w[donor volunteer]).each do |role|
        Notification.create!(deduplication_key: "welcome:#{role}:#{user.id}", recipient_user_id: user.id,
          channel: "email", destination: user.email, template_key: "welcome_#{role}",
          payload_json: { first_name: user.first_name })
      end
    end
    redirect_to new_session_path, notice: "Email verified. You can sign in."
  end
end
