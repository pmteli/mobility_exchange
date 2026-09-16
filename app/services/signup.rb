class Signup
  def self.call(attributes)
    roles = Array(attributes[:community_roles]).reject(&:blank?).uniq
    raise Workflow::Error, "Select at least one role: Volunteer, Donor, or Recipient." if roles.empty? || (roles - %w[volunteer donor recipient]).any?
    MobilityTransaction.call do
      user = User.create!(attributes.slice(:email, :first_name, :last_name).merge(community_roles: roles, auth_subject: "local:#{SecureRandom.uuid}"))
      Credential.create!(user: user, password: attributes[:password], password_confirmation: attributes[:password_confirmation])
      UserRole.create!(user_id: user.id, role_id: "public", assigned_by: user.id)
      Notification.create!(deduplication_key: "verify:#{user.id}", recipient_user_id: user.id, channel: "email", destination: user.email, template_key: "verification", payload_json: { token: AccountTokens.issue(user, "verify") })
      user
    end
  end
end
