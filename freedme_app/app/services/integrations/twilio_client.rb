require "net/http"
require "json"

module Integrations
  # FR003/FR018: explicit opt-in; recording instances can never send real SMS.
  class TwilioClient
    class DeliveryError < StandardError; end
    def self.live?
      ENV["FREEDME_RECORDING_MODE"] != "true" && ENV.fetch("SMS_PROVIDER", "simulated") == "twilio"
    end

    def post(host, path, fields)
      raise DeliveryError, "Twilio messaging is disabled." unless self.class.live?
      sid = ENV.fetch("TWILIO_ACCOUNT_SID")
      token = ENV.fetch("TWILIO_AUTH_TOKEN")
      raise DeliveryError, "Invalid Twilio account configuration." unless sid.match?(/\AAC[0-9a-fA-F]{32}\z/) && token.present?
      uri = URI::HTTPS.build(host: host, path: path)
      request = Net::HTTP::Post.new(uri)
      request.basic_auth(sid, token)
      request.set_form_data(fields)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 15, write_timeout: 10) { |http| http.request(request) }
      # Never log provider response bodies: they may include phone numbers or OTPs.
      raise DeliveryError, "Twilio request failed (HTTP #{response.code})." unless response.is_a?(Net::HTTPSuccess)
      JSON.parse(response.body)
    rescue KeyError, JSON::ParserError, IOError, SystemCallError, Timeout::Error, OpenSSL::SSL::SSLError
      raise DeliveryError, "Messaging service is unavailable. Please try again later."
    end

    def start_verification(phone)
      post("verify.twilio.com", "/v2/Services/#{verify_sid}/Verifications", {To: phone, Channel: "sms"}).fetch("sid")
    end

    def check_verification(sid, code)
      post("verify.twilio.com", "/v2/Services/#{verify_sid}/VerificationCheck", {VerificationSid: sid, Code: code})["status"] == "approved"
    end

    def send_message(to:, body:)
      account = ENV.fetch("TWILIO_ACCOUNT_SID")
      post("api.twilio.com", "/2010-04-01/Accounts/#{account}/Messages.json",
        {To: to, Body: body, MessagingServiceSid: ENV.fetch("TWILIO_MESSAGING_SERVICE_SID")}).fetch("sid")
    end

    private
    def verify_sid
      ENV.fetch("TWILIO_VERIFY_SERVICE_SID")
    end
  end
end
