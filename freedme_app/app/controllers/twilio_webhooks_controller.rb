require "base64"

# Provider callbacks are form-encoded and authenticated using the configured public URL.
class TwilioWebhooksController < ActionController::Base
  skip_forgery_protection
  before_action :verify_signature!

  def status
    delivery = SmsDelivery.find_by(provider_sid: params[:MessageSid])
    if delivery && %w[accepted queued sending sent delivered undelivered failed canceled].include?(params[:MessageStatus])
      delivery.with_lock do
        unless %w[delivered undelivered failed canceled].include?(delivery.delivery_status)
          delivery.update!(delivery_status: params[:MessageStatus], error_code: params[:ErrorCode].to_s.presence)
        end
      end
    end
    head :no_content
  end

  def incoming
    # Advanced Opt-Out handles the carrier response. Do not send a duplicate reply.
    if params[:OptOutType] == "STOP" && params[:MessageSid].present?
      hmac = Journeys::Support.digest(params[:From].to_s)
      contact = AccountContact.find_by(kind: "mobile", lookup_hmac: hmac, revoked_at: nil)
      if contact
        ConsentEvent.create_or_find_by!(idempotency_key: "twilio-stop-#{params[:MessageSid]}") do |event|
          event.assign_attributes(account_id: contact.account_id, contact_id: contact.id,
            purpose: "routine_sms", action: "stop")
        end
      end
    end
    # START recovery and YES/NO transaction replies require separate approved rules (DEC05).
    render plain: "<Response/>", content_type: "text/xml"
  end

  private
  # FR018/FR027: permit signed callback testing without enabling outbound SMS.
  def callbacks_enabled?
    ENV["FREEDME_RECORDING_MODE"] != "true" &&
      (Integrations::TwilioClient.live? || ENV["TWILIO_WEBHOOKS_ENABLED"] == "true")
  end

  def verify_signature!
    base = ENV["TWILIO_WEBHOOK_BASE_URL"].to_s.delete_suffix("/")
    token = ENV["TWILIO_AUTH_TOKEN"].to_s
    return head :forbidden unless callbacks_enabled? && base.start_with?("https://") && token.present? && request.media_type == "application/x-www-form-urlencoded" && request.query_string.empty?
    fields = request.request_parameters
    return head :forbidden unless fields.values.all? { |v| v.is_a?(String) }
    data = base + request.path + fields.sort.map { |k, v| k + v }.join
    expected = Base64.strict_encode64(OpenSSL::HMAC.digest("sha1", token, data))
    return head :forbidden unless ActiveSupport::SecurityUtils.secure_compare(expected, request.headers["X-Twilio-Signature"].to_s)
    head :forbidden unless params[:AccountSid] == ENV["TWILIO_ACCOUNT_SID"]
  end
end
