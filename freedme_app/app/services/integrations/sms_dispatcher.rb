module Integrations
  class SmsDispatcher
    def self.run!(client: TwilioClient.new)
      return unless TwilioClient.live?
      50.times do
        delivery = SmsDelivery.transaction do
          row = SmsDelivery.where(state: "queued").order(:created_at).lock("FOR UPDATE SKIP LOCKED").first
          if row
            row.update!(state: SmsConsent.allowed?(row.recipient_hmac, account_id: row.recipient_account_id) ? "sending" : "suppressed")
          end
          row
        end
        break unless delivery
        next unless delivery.state == "sending"
        begin
          sid = client.send_message(to: Journeys::Support.decrypt(delivery.recipient_ciphertext), body: Journeys::Support.decrypt(delivery.body_ciphertext))
          delivery.update!(state: "accepted", provider_sid: sid)
        rescue TwilioClient::DeliveryError, KeyError
          # No blind retries: a timeout may occur after Twilio accepted the SMS.
          delivery.update!(state: "failed", error_code: "provider_error_or_unknown_outcome")
        end
      end
    end
  end
end
