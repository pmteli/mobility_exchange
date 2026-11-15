module Integrations
  module SmsConsent
    def self.allowed?(hmac)
      contact = AccountContact.find_by(kind: "mobile", lookup_hmac: hmac, revoked_at: nil)
      return false unless contact && contact.account.status == "active"
      return false if carrier_stopped?(contact)
      ConsentEvent.where(contact_id: contact.id, purpose: "routine_sms").order(occurred_at: :desc, id: :desc).first&.action == "granted"
    end

    def self.carrier_stopped?(contact)
      ConsentEvent.where(contact_id: contact.id, purpose: "routine_sms", action: ["stop", "reset"]).order(occurred_at: :desc, id: :desc).first&.action == "stop"
    end

    def self.grant!(account, key:)
      contact = AccountContact.find_by!(account_id: account.id, kind: "mobile", revoked_at: nil)
      ConsentEvent.create!(account_id: account.id, contact_id: contact.id, purpose: "routine_sms", action: "granted", idempotency_key: key)
    end
  end
end
