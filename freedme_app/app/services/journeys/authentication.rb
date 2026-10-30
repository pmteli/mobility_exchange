module Journeys
  class Authentication
    class RegistrationRequired < Error; end

    def self.start!(mobile:, name: nil, locality: nil, registration: false)
      Support.guard!
      phone = Support.phone(mobile)
      hmac = Support.digest(phone)
      contact = AccountContact.find_by(kind: "mobile", lookup_hmac: hmac, revoked_at: nil)
      account = contact&.account
      Support.active!(account) if account
      raise RegistrationRequired, "This mobile number is not registered. Please create an account." if !account && !registration
      raise Error, "This mobile number is already registered. Please sign in instead." if account && registration
      if registration && (name.to_s.strip.empty? || locality.to_s.strip.empty?)
        raise Error, "New users: enter a display name and approximate ZIP or town."
      end
      raise Error, "Display name or location is too long." if name.to_s.length > 80 || locality.to_s.length > 160
      challenge = nil
      code = SecureRandom.random_number(1_000_000).to_s.rjust(6, "0")
      ApplicationRecord.transaction do
        # Serialize all challenges for this phone, including unregistered numbers.
        ApplicationRecord.connection.execute("SELECT pg_advisory_xact_lock(#{hmac.unpack1('q>')})")
        recent = AuthChallenge.where(phone_lookup_hmac: hmac).where("created_at > ?", 1.hour.ago)
        raise Error, "Too many codes. Try again later." if recent.count >= 5
        raise Error, "Wait one minute before requesting another code." if recent.where("created_at > ?", 1.minute.ago).exists?
        AuthChallenge.where(phone_lookup_hmac: hmac, consumed_at: nil, invalidated_at: nil).update_all(invalidated_at: Time.current)
        challenge = AuthChallenge.create!(account_id: account&.id, phone_lookup_hmac: hmac, code_digest: Support.digest(code), expires_at: 10.minutes.from_now)
        Integrations::SmsGateway.new.deliver(to: phone, template: "sign_in_otp", parameters: { code: code, expiry_minutes: 10 }, idempotency_key: "otp-#{challenge.id}")
      end
      { "challenge_id" => challenge.id, "phone" => phone, "name" => name.to_s.strip, "locality" => locality.to_s.strip, "registration" => registration }
    end
    def self.verify!(pending, code)
      Support.guard!
      raise Error, "Request a new sign-in code." unless pending
      account = nil
      failure = nil
      AuthChallenge.transaction do
        challenge = AuthChallenge.lock.find(pending.fetch("challenge_id"))
        if challenge.consumed_at || challenge.invalidated_at || challenge.expires_at <= Time.current
          failure = "This code has expired or was already used. Request a new code."
        elsif !ActiveSupport::SecurityUtils.secure_compare(challenge.code_digest, Support.digest(code))
          attempts = challenge.failed_attempts + 1
          challenge.update!(failed_attempts: attempts, invalidated_at: attempts >= 3 ? Time.current : nil)
          failure = "Incorrect code. #{3-attempts} attempts remaining."
        else
          account = challenge.account
          if !account
            account = Account.create!(display_name: pending.fetch("name"), public_locality: pending.fetch("locality"))
            %w[donor recipient].each { |role| AccountRole.create!(account_id: account.id, role: role) }
            AccountContact.create!(account_id: account.id, kind: "mobile", value_ciphertext: Support.encrypt(pending.fetch("phone")),
              lookup_hmac: challenge.phone_lookup_hmac, key_version: "fictional-seed-v1", verified_at: Time.current)
            Support.notify(account, "registration_welcome", {display_name: account.display_name})
          end
          Support.active!(account)
          challenge.update!(consumed_at: Time.current, account_id: account.id)
        end
      end
      raise Error, failure if failure
      account
    end
  end
end
