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
    end
    redirect_to new_session_path, notice: "Email verified. You can sign in."
  end
end
