module Staff
  # Invoked by the root-only operator command; never exposed as an HTTP action.
  class Provisioner
    def self.create!(email:, username:, password:, first_name:, last_name:, role:)
      raise ArgumentError, 'Role must be moderator or administrator.' unless %w[moderator administrator].include?(role)
      email = email.to_s.strip.downcase
      username = username.to_s.strip.downcase
      raise ArgumentError, 'Enter a valid email address.' unless email.match?(/\A[^\s@]+@[^\s@]+\.[^\s@]+\z/)
      raise ArgumentError, 'Username must be 3–40 letters, numbers, periods, hyphens or underscores.' unless username.match?(/\A[a-z0-9][a-z0-9._-]{2,39}\z/)
      raise ArgumentError, 'First and last names are required.' if first_name.to_s.strip.empty? || last_name.to_s.strip.empty?
      raise ArgumentError, 'Use a password of at least 8 characters and at most 72 bytes.' unless password.length >= 8 && password.bytesize <= 72
      Account.transaction do
        hmac = Journeys::Support.digest(email)
        raise ArgumentError, 'Email is already registered.' if AccountContact.exists?(kind: 'email', lookup_hmac: hmac, revoked_at: nil)
        account = Account.create!(display_name: "#{first_name.strip} #{last_name.strip}", public_locality: 'Bay Area, California')
        AccountRole.create!(account_id: account.id, role: role)
        AccountRole.create!(account_id: account.id, role: 'moderator') if role == 'administrator'
        contact = AccountContact.create!(account_id: account.id, kind: 'email', lookup_hmac: hmac, value_ciphertext: Journeys::Support.encrypt(email), key_version: 'fictional-seed-v1')
        credential = StaffCredential.create!(account_id: account.id, email_contact_id: contact.id, username: username, password: password,
          first_name_ciphertext: Journeys::Support.encrypt(first_name.strip), last_name_ciphertext: Journeys::Support.encrypt(last_name.strip),
          mfa_secret_ciphertext: Journeys::Support.encrypt(ROTP::Base32.random), key_version: 'fictional-seed-v1', session_version: SecureRandom.hex(32))
        audit!(account, 'staff_provisioned')
        credential
      end
    end
    def self.reset!(identifier, password)
      raise ArgumentError, 'Use a password of at least 8 characters and at most 72 bytes.' unless password.length >= 8 && password.bytesize <= 72
      credential = Authentication.find(identifier) or raise ArgumentError, 'Staff account not found.'
      credential.with_lock do
        credential.update!(password: password, mfa_secret_ciphertext: Journeys::Support.encrypt(ROTP::Base32.random), mfa_enrolled_at: nil,
          last_totp_at: nil, failed_attempts: 0, locked_until: nil, session_version: SecureRandom.hex(32))
        audit!(credential.account, 'staff_credentials_reset')
      end
      credential
    end
    def self.audit!(account, action)
      AuditEvent.create!(action: action, entity_type: 'Account', entity_id: account.id, reason_code: 'server_operator', correlation_id: SecureRandom.uuid)
    end
  end
end
