module Journeys
  # FR003/FR018: verify ownership, preserve old consent history, and never transfer consent.
  class MobileChange
    def self.start!(account, mobile, client: Integrations::TwilioClient.new)
      Support.guard!
      Support.active!(account)
      phone = Support.phone(mobile)
      hmac = Support.digest(phone)
      challenge = nil
      AuthChallenge.transaction do
        ApplicationRecord.connection.execute("SELECT pg_advisory_xact_lock(#{hmac.unpack1('q>')})")
        raise Error, 'This mobile number is already registered.' if (!Staff::Authentication.staff?(account) && AccountContact.exists?(kind: 'mobile', lookup_hmac: hmac, revoked_at: nil, staff_notification: false))
        recent = AuthChallenge.where(phone_lookup_hmac: hmac).where('created_at > ?', 1.hour.ago)
        raise Error, 'Too many codes. Try again later.' if recent.count >= 5
        raise Error, 'Wait one minute before requesting another code.' if recent.where('created_at > ?', 1.minute.ago).exists?
        AuthChallenge.where(phone_lookup_hmac: hmac, consumed_at: nil, invalidated_at: nil).update_all(invalidated_at: Time.current)
        code = SecureRandom.random_number(1_000_000).to_s.rjust(6, '0')
        challenge = AuthChallenge.create!(account_id: account.id, phone_lookup_hmac: hmac, code_digest: Support.digest(code), provider: Integrations::TwilioClient.live? ? 'twilio' : 'simulated', expires_at: 10.minutes.from_now)
        if challenge.provider == 'twilio'
          challenge.update!(provider_sid: client.start_verification(phone))
        else
          Integrations::SmsGateway.new.deliver(to: phone, template: 'sign_in_otp', parameters: {code: code, expiry_minutes: 10}, idempotency_key: "mobile-change-#{challenge.id}")
        end
      end
      {'challenge_id' => challenge.id, 'phone' => phone}
    rescue Integrations::TwilioClient::DeliveryError, KeyError
      raise Error, 'Unable to send the verification code. Please try again later.'
    end

    def self.confirm!(account, old_contact_id, pending, code, client: Integrations::TwilioClient.new, staff_enrollment: false)
      Support.guard!
      raise Error, 'Request a code for your new number.' unless pending
      failure = nil
      account.with_lock do
        Support.active!(account)
        if staff_enrollment
          raise Error, 'Staff access required.' unless Staff::Authentication.staff?(account)
          raise Error, 'A mobile number is already configured.' if AccountContact.exists?(account_id: account.id, kind: 'mobile', revoked_at: nil)
          old = nil
        else
          old = AccountContact.find_by!(id: old_contact_id, account_id: account.id, kind: 'mobile', revoked_at: nil)
        end
        challenge = AuthChallenge.lock.find(pending.fetch('challenge_id'))
        phone = Support.phone(pending.fetch('phone'))
        unless challenge.account_id == account.id && challenge.phone_lookup_hmac == Support.digest(phone)
          raise Error, 'This verification does not belong to your account.'
        end
        if challenge.consumed_at || challenge.invalidated_at || challenge.expires_at <= Time.current
          failure = 'This code expired or was already used. Request another code.'
        elsif !Authentication.valid_code?(challenge, code, client: client)
          attempts = challenge.failed_attempts + 1
          challenge.update!(failed_attempts: attempts, invalidated_at: attempts >= 3 ? Time.current : nil)
          failure = "Incorrect code. #{[3-attempts, 0].max} attempts remaining."
        else
          hmac = challenge.phone_lookup_hmac
          ApplicationRecord.connection.execute("SELECT pg_advisory_xact_lock(#{hmac.unpack1('q>')})")
          raise Error, 'This mobile number is already registered.' if (!Staff::Authentication.staff?(account) && AccountContact.exists?(kind: 'mobile', lookup_hmac: hmac, revoked_at: nil, staff_notification: false))
          previous = AccountContact.where(kind: 'mobile', lookup_hmac: hmac).select(:id)
          carrier_event = ConsentEvent.where(contact_id: previous, purpose: 'routine_sms', action: %w[stop reset]).order(occurred_at: :desc, id: :desc).first
          old&.update!(revoked_at: Time.current)
          contact = AccountContact.create!(account_id: account.id, kind: 'mobile', lookup_hmac: hmac, value_ciphertext: Support.encrypt(phone), key_version: old&.key_version || "fictional-seed-v1", verified_at: Time.current)
          if carrier_event&.action == 'stop'
            ConsentEvent.create!(account_id: account.id, contact_id: contact.id, purpose: 'routine_sms', action: 'stop', idempotency_key: "mobile-change-stop-#{challenge.id}")
          end
          SmsDelivery.where(recipient_account_id: account.id, recipient_hmac: old.lookup_hmac, state: 'queued').update_all(state: 'suppressed', updated_at: Time.current) if old
          AuthChallenge.where(account_id: account.id, phone_lookup_hmac: old.lookup_hmac, consumed_at: nil, invalidated_at: nil).update_all(invalidated_at: Time.current) if old
          challenge.update!(consumed_at: Time.current)
          AuditEvent.create!(actor_id: account.id, action: 'mobile_changed', entity_type: 'Account', entity_id: account.id, reason_code: 'verified_mobile_change', correlation_id: SecureRandom.uuid)
        end
      end
      raise Error, failure if failure
      true
    rescue ActiveRecord::RecordNotUnique
      raise Error, 'This mobile number is already registered.'
    rescue ActiveRecord::RecordNotFound, KeyError
      raise Error, 'Restart mobile verification and try again.'
    rescue Integrations::TwilioClient::DeliveryError
      raise Error, 'Verification service is unavailable. Please try again later.'
    end
  end
end
