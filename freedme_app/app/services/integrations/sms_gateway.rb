module Integrations
  class SmsGateway
    def deliver(to:, template:, parameters:, idempotency_key: nil, account_id: nil)
      unless Journeys::Support.enabled?
        raise NotConfigured, "SMS is not configured; no external request was sent."
      end
      if account_id.nil?
        owners = AccountContact.where(kind: "mobile", revoked_at: nil, lookup_hmac: Journeys::Support.digest(to)).limit(2).pluck(:account_id)
        account_id = owners.first if owners.one?
      end
      body = I18n.interpolate(I18n.t!("sms.#{template}"), parameters.symbolize_keys.merge(link: SmsLinks.url(template)))
      if TwilioClient.live?
        body += " " + I18n.t!("sms_delivery.opt_out_footer")
        return SmsDelivery.create_or_find_by!(idempotency_key: idempotency_key || SecureRandom.uuid) do |message|
          message.assign_attributes(recipient_account_id: account_id, recipient_ciphertext: Journeys::Support.encrypt(to),
            recipient_hmac: Journeys::Support.digest(to), body_ciphertext: Journeys::Support.encrypt(body), template_code: template)
        end
      end
      attributes = { recipient_account_id: account_id, recipient: to, template_code: template, body: body }
      if idempotency_key
        SimulatedSmsMessage.create_or_find_by!(idempotency_key: idempotency_key) { |message| message.assign_attributes(attributes) }
      else
        SimulatedSmsMessage.create!(attributes)
      end
    end
  end
end
