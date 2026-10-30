module Journeys
  module Support
    def self.enabled?
      Rails.env.development? || Rails.env.test?
    end
    def self.guard!
      raise Error, "Local simulated workflows are disabled in production." unless enabled?
    end
    def self.key
      Rails.application.key_generator.generate_key("freedme fictional seed contacts v1", 32)
    end
    def self.encrypt(value)
      ActiveSupport::MessageEncryptor.new(key).encrypt_and_sign(value.to_s)
    end
    def self.decrypt(value)
      ActiveSupport::MessageEncryptor.new(key).decrypt_and_verify(value)
    end
    def self.digest(value)
      OpenSSL::HMAC.digest("SHA256", key, value.to_s)
    end
    def self.phone(value)
      digits = value.to_s.gsub(/\D/, "")
      digits = "1#{digits}" if digits.length == 10
      raise Error, "Enter a US mobile number with 10 digits." unless digits.match?(/\A1[2-9]\d{9}\z/)
      "+#{digits}"
    end
    def self.notify(account, template, parameters = {}, key: SecureRandom.uuid)
      guard!
      contact = AccountContact.find_by!(account_id: account.id, kind: "mobile", revoked_at: nil)
      Integrations::SmsGateway.new.deliver(to: decrypt(contact.value_ciphertext), template: template,
        parameters: parameters, idempotency_key: key)
    end
    def self.audit(actor, action, record)
      AuditEvent.create!(actor_id: actor.id, action: action, entity_type: record.class.name,
        entity_id: record.id, reason_code: "local_simulation", correlation_id: SecureRandom.uuid)
    end
    def self.active!(actor, listing = nil)
      raise Error, "This account is not active." unless actor.status == "active"
      holds = Restriction.where(released_at: nil)
      raise Error, "An account restriction prevents this action." if holds.where(account_id: actor.id).exists?
      raise Error, "An equipment restriction prevents this action." if listing && holds.where(listing_id: listing.id).exists?
    end
  end
end
