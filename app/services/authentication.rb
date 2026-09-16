class Authentication
  class Invalid < StandardError; end
  def self.login(email:, password:, otp: nil)
    MobilityTransaction.call do
      user = User.find_by("lower(email) = ?", email.to_s.strip.downcase)
      credential = user&.credential
      # Perform a password hash check even for unknown users.
      valid = credential ? credential.authenticate(password.to_s) : BCrypt::Password.new(dummy_digest).is_password?(password.to_s)
      raise Invalid unless valid && user.account_status == "active" && user.email_verified_at
      user.update!(last_login_at: Time.current)
      LoginSession.create!(user: user, expires_at: 12.hours.from_now)
    end
  end
  def self.dummy_digest
    @dummy_digest ||= BCrypt::Password.create(SecureRandom.hex(32)).to_s
  end
end
