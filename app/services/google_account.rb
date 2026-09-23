class GoogleAccount
  def self.login(identity)
    MobilityTransaction.call do
      user = User.find_by(google_subject: identity.fetch("sub"))
      user && start_session(user)
    end
  end

  def self.complete(identity, attributes)
    MobilityTransaction.call do
      # A concurrent completion must never link the same Google identity twice.
      raise Workflow::Error, "This Google account is already connected. Please sign in again." if User.exists?(google_subject: identity.fetch("sub"))
      user = User.find_by("lower(email) = ?", identity.fetch("email"))
      if user
        valid = user.credential&.authenticate(attributes[:password].to_s)
        unless valid && user.account_status == "active" && user.email_verified_at && user.google_subject.nil?
          raise Workflow::Error, "We could not link this account. Check your password and account verification, or use password reset."
        end
        user.update!(google_subject: identity.fetch("sub"))
      else
        roles = Array(attributes[:community_roles]).reject(&:blank?).uniq
        if roles.empty? || (roles - %w[donor volunteer recipient]).any?
          raise Workflow::Error, "Select at least one role: Volunteer, Donor, or Recipient."
        end
        user = User.create!(email: identity.fetch("email"), first_name: attributes[:first_name], last_name: attributes[:last_name],
          google_subject: identity.fetch("sub"), auth_subject: "google:#{identity.fetch('sub')}",
          community_roles: roles, email_verified_at: Time.current, account_status: "active")
        # Retains the existing secure password-reset flow. This random password is never disclosed.
        password = SecureRandom.hex(32)
        Credential.create!(user: user, password: password, password_confirmation: password)
        UserRole.create!(user_id: user.id, role_id: "public", assigned_by: user.id)
        (roles & %w[donor volunteer]).each do |role|
          Notification.create!(deduplication_key: "welcome:#{role}:#{user.id}", recipient_user_id: user.id,
            channel: "email", destination: user.email, template_key: "welcome_#{role}", payload_json: { first_name: user.first_name })
        end
      end
      start_session(user)
    end
  end

  def self.start_session(user)
    raise Workflow::Error, "This account is not eligible to sign in." unless user.account_status == "active" && user.email_verified_at
    user.update!(last_login_at: Time.current)
    LoginSession.create!(user: user, expires_at: 12.hours.from_now)
  end
  private_class_method :start_session
end
