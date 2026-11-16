module Staff
  # FR003, NFR003: staff authentication is separate from member mobile OTP.
  class Authentication
    class Error < StandardError; end
    GENERIC_ERROR = 'Unable to sign in. Check your details or try again later.'
    def self.staff?(account)
      account && AccountRole.exists?(account_id: account.id, role: %w[moderator administrator])
    end
    def self.find(identifier)
      value = identifier.to_s.strip.downcase
      contact = AccountContact.find_by(kind: 'email', lookup_hmac: Journeys::Support.digest(value), revoked_at: nil)
      contact ? StaffCredential.find_by(email_contact_id: contact.id) : StaffCredential.find_by(username: value)
    end
    def self.password!(identifier, password)
      credential = find(identifier)
      unless credential
        BCrypt::Password.new(dummy_hash).is_password?(password.to_s)
        raise Error, GENERIC_ERROR
      end
      valid = false
      credential.with_lock do
        eligible!(credential)
        valid = credential.authenticate(password.to_s).present?
        fail_attempt!(credential) unless valid
      end
      raise Error, GENERIC_ERROR unless valid
      credential
    end
    def self.dummy_hash
      @dummy_hash ||= BCrypt::Password.create(SecureRandom.hex(24)).to_s
    end
    def self.eligible!(credential)
      raise Error, GENERIC_ERROR unless staff?(credential.account) && credential.account.status == 'active'
      raise Error, GENERIC_ERROR if credential.locked_until && credential.locked_until > Time.current
      Journeys::Support.active!(credential.account)
    rescue Journeys::Error
      raise Error, GENERIC_ERROR
    end
    def self.fail_attempt!(credential)
      attempts = credential.locked_until && credential.locked_until <= Time.current ? 1 : credential.failed_attempts + 1
      credential.update!(failed_attempts: attempts, locked_until: attempts >= 5 ? 15.minutes.from_now : nil)
    end
    def self.totp(credential)
      ROTP::TOTP.new(Journeys::Support.decrypt(credential.mfa_secret_ciphertext), issuer: 'FreeDME Staff')
    end
    def self.verify!(credential, code)
      valid = false
      credential.with_lock do
        eligible!(credential)
        timestamp = code.to_s.match?(/\A\d{6}\z/) && totp(credential).verify(code.to_s, drift_behind: 30, drift_ahead: 30, after: credential.last_totp_at)
        if timestamp
          credential.update!(last_totp_at: timestamp, mfa_enrolled_at: credential.mfa_enrolled_at || Time.current, failed_attempts: 0, locked_until: nil)
          credential.account.update!(last_activity_at: Time.current)
          AuditEvent.create!(actor_id: credential.account_id, action: 'staff_signed_in', entity_type: 'Account', entity_id: credential.account_id, reason_code: 'password_and_totp', correlation_id: SecureRandom.uuid)
          valid = true
        else
          fail_attempt!(credential)
        end
      end
      raise Error, 'Invalid or already used authenticator code. Try again with a new code.' unless valid
      credential.account
    end
  end
end
