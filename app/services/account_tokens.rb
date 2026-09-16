class AccountTokens
  def self.issue(user, purpose)
    Rails.application.message_verifier("account").generate(
      { "id" => user.id, "nonce" => user.credential.token_nonce, "email" => user.email },
      purpose: purpose, expires_in: purpose == "reset" ? 30.minutes : 24.hours)
  end
  def self.resolve(token, purpose)
    data = Rails.application.message_verifier("account").verified(token, purpose: purpose)
    return unless data
    user = User.find_by(id: data["id"])
    user if user && user.credential && ActiveSupport::SecurityUtils.secure_compare(user.credential.token_nonce, data["nonce"]) && user.email == data["email"]
  end
end
