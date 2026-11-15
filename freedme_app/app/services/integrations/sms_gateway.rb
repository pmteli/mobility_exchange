module Integrations
  class SmsGateway
    def deliver(to:, template:, parameters:, idempotency_key: nil)
      unless Journeys::Support.enabled?
        raise NotConfigured, "SMS is not configured; no external request was sent."
      end
      body = I18n.interpolate(I18n.t!("sms.#{template}"), parameters.symbolize_keys.merge(link: SmsLinks.url(template)))
      if TwilioClient.live?
        body += " " + I18n.t!("sms_delivery.opt_out_footer")
        return SmsDelivery.create_or_find_by!(idempotency_key: idempotency_key || SecureRandom.uuid) do |message|
          message.assign_attributes(recipient_ciphertext: Journeys::Support.encrypt(to),
            recipient_hmac: Journeys::Support.digest(to), body_ciphertext: Journeys::Support.encrypt(body), template_code: template)
        end
      end
      attributes = { recipient: to, template_code: template, body: body }
      if idempotency_key
        SimulatedSmsMessage.create_or_find_by!(idempotency_key: idempotency_key) { |message| message.assign_attributes(attributes) }
      else
        SimulatedSmsMessage.create!(attributes)
      end
    end
  end
end
