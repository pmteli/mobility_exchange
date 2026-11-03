module Integrations
  class SmsGateway
    def deliver(to:, template:, parameters:, idempotency_key: nil)
      unless Rails.env.development? || Rails.env.test?
        raise NotConfigured, "SMS is not configured; no external request was sent."
      end
      body = I18n.interpolate(I18n.t!("sms.#{template}"), parameters.symbolize_keys.merge(link: SmsLinks.url(template)))
      attributes = { recipient: to, template_code: template, body: body }
      if idempotency_key
        SimulatedSmsMessage.create_or_find_by!(idempotency_key: idempotency_key) { |message| message.assign_attributes(attributes) }
      else
        SimulatedSmsMessage.create!(attributes)
      end
    end
  end
end
