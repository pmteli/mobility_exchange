class UpdateProfile
  FIELDS = %i[first_name last_name phone address_line1 address_line2 city region postal_code].freeze

  def self.call(user, attributes, current_password:)
    Workflow.run do
      user.reload
      email = attributes.fetch(:email, user.email).to_s.strip.downcase
      email_changed = email != user.email && (email != user.pending_email || current_password.present?)
      if email_changed
        raise Workflow::Error, "Enter your current password to change your email." unless user.credential&.authenticate(current_password.to_s)
        raise Workflow::Error, "This email address is already in use." if User.where.not(id: user.id).where("lower(email) = ?", email).exists?
        user.pending_email = email
        user.pending_email_nonce = SecureRandom.hex(32)
      elsif email == user.email
        user.pending_email = user.pending_email_nonce = nil
      end
      user.assign_attributes(attributes.slice(*FIELDS).transform_values { |value| value.to_s.strip })
      user.save!
      sync_contacts!(user, attributes.keys & FIELDS)
      if email_changed
        token = Rails.application.message_verifier("profile_email").generate(
          { id: user.id, email: user.pending_email, nonce: user.pending_email_nonce }, expires_in: 24.hours)
        Notification.create!(deduplication_key: "email-change:#{SecureRandom.uuid}", recipient_user_id: user.id,
          channel: "email", destination: user.pending_email, template_key: "email_change", payload_json: { token: token })
      end
      Audit.record!(user, "profile.updated", user)
      user
    end
  end

  def self.sync_contacts!(user, fields)
    [user.donor, user.recipient].compact.each do |record|
      record.update!(user.attributes.slice(*(fields.map(&:to_s))))
    end
  end

  def self.resolve(token)
    data = Rails.application.message_verifier("profile_email").verified(token)
    return unless data
    data = data.with_indifferent_access
    user = User.find_by(id: data[:id], account_status: "active")
    user if user&.pending_email.present? && user.pending_email == data[:email] && user.pending_email_nonce == data[:nonce]
  end

  def self.confirm(token)
    Workflow.run do
      user = resolve(token) or raise ActiveRecord::RecordNotFound
      user.update!(email: user.pending_email, pending_email: nil, pending_email_nonce: nil, email_verified_at: Time.current)
      user.credential.update!(token_nonce: SecureRandom.hex(32))
      LoginSession.where(user_id: user.id).delete_all
      sync_contacts!(user, [:email])
      Audit.record!(user, "profile.email_confirmed", user)
    end
  end
end
