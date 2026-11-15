require "test_helper"
require "base64"
require Rails.root.join("db/seeds/journeys")

class TwilioWebhooksTest < ActionDispatch::IntegrationTest
  setup do
    @keys = %w[SMS_PROVIDER TWILIO_WEBHOOKS_ENABLED TWILIO_AUTH_TOKEN TWILIO_ACCOUNT_SID TWILIO_WEBHOOK_BASE_URL FREEDME_RECORDING_MODE]
    @old = ENV.to_h.slice(*@keys)
    ENV.delete("TWILIO_WEBHOOKS_ENABLED")
    ENV["SMS_PROVIDER"] = "twilio"
    ENV["TWILIO_AUTH_TOKEN"] = "test-secret"
    ENV["TWILIO_ACCOUNT_SID"] = "ACtest"
    ENV["TWILIO_WEBHOOK_BASE_URL"] = "https://example.org"
    ENV.delete("FREEDME_RECORDING_MODE")
    load Rails.root.join("db/seeds.rb")
    JourneySeeds.load!
  end
  teardown do
    @keys.each { |k| @old.key?(k) ? ENV[k] = @old[k] : ENV.delete(k) }
  end
  def callback(path, fields, valid: true)
    fields = fields.merge("AccountSid" => "ACtest")
    signature = Base64.strict_encode64(OpenSSL::HMAC.digest("sha1", "test-secret", "https://example.org#{path}" + fields.sort.map { |k,v| k+v }.join))
    post path, params: fields, headers: {"X-Twilio-Signature" => valid ? signature : "bad"}
  end
  test "live activity renders preferences and cannot bypass STOP by toggling off then on" do
    ENV["SMS_PROVIDER"] = "simulated"
    post sign_in_path, params: {mobile: "+15105550101"}
    code = SimulatedSmsMessage.where(recipient: "+15105550101", template_code: "sign_in_otp").order(created_at: :desc).first!.body[/code: (\d+)/, 1]
    post verify_sign_in_path, params: {code: code}
    ENV["SMS_PROVIDER"] = "twilio"
    get activity_path
    assert_response :success
    assert_select "button", text: "SMS Messages"
    patch sms_preferences_path, params: {sms_consent: "1"}
    assert Integrations::SmsConsent.allowed?(Journeys::Support.digest("+15105550101"))
    callback('/webhooks/twilio/incoming', {"From" => "+15105550101", "OptOutType" => "STOP", "MessageSid" => "SMtoggle"})
    patch sms_preferences_path, params: {sms_consent: "0"}
    patch sms_preferences_path, params: {sms_consent: "1"}
    refute Integrations::SmsConsent.allowed?(Journeys::Support.digest("+15105550101"))
  end
  test "callback-only mode handles STOP without enabling outbound messages" do
    ENV["SMS_PROVIDER"] = "simulated"
    ENV["TWILIO_WEBHOOKS_ENABLED"] = "true"
    account = Account.find(JourneySeeds.id(1))
    Integrations::SmsConsent.grant!(account, key: "callback-only-consent")
    callback('/webhooks/twilio/incoming', {"From" => "+15105550101", "OptOutType" => "STOP", "MessageSid" => "SMcallbackonly"})
    assert_response :success
    refute Integrations::SmsConsent.allowed?(Journeys::Support.digest("+15105550101"))
    refute Integrations::TwilioClient.live?
    callback('/webhooks/twilio/incoming', {"From" => "+15105550101", "OptOutType" => "STOP", "MessageSid" => "SMforged"}, valid: false)
    assert_response :forbidden
  end
  test "simulated and recording environments reject callbacks by default" do
    ENV["SMS_PROVIDER"] = "simulated"
    callback('/webhooks/twilio/incoming', {"MessageSid" => "SMdisabled"})
    assert_response :forbidden
    ENV["TWILIO_WEBHOOKS_ENABLED"] = "true"
    ENV["FREEDME_RECORDING_MODE"] = "true"
    callback('/webhooks/twilio/incoming', {"MessageSid" => "SMrecording"})
    assert_response :forbidden
  end
  test "unsigned webhook rejected" do
    callback('/webhooks/twilio/incoming', {"From" => "+15105550101", "OptOutType" => "STOP", "MessageSid" => "SMstop"}, valid: false)
    assert_response :forbidden
  end
  test "signed STOP is idempotent and withdraws consent" do
    account = Account.find(JourneySeeds.id(1))
    Integrations::SmsConsent.grant!(account, key: "prior-consent")
    assert_difference "ConsentEvent.count", 1 do
      2.times do
        callback('/webhooks/twilio/incoming', {"From" => "+15105550101", "OptOutType" => "STOP", "MessageSid" => "SMstop"})
        assert_response :success
      end
    end
    refute Integrations::SmsConsent.allowed?(Journeys::Support.digest("+15105550101"))
  end
  test "terminal delivery status cannot be regressed by late callback" do
    row = SmsDelivery.create!(recipient_ciphertext: "encrypted", recipient_hmac: "test", body_ciphertext: "encrypted", template_code: "listing_published", idempotency_key: "status", state: "accepted", provider_sid: "SMstatus")
    %w[delivered sent].each do |status|
      callback('/webhooks/twilio/status', {"MessageSid" => "SMstatus", "MessageStatus" => status})
      assert_response :no_content
    end
    assert_equal "delivered", row.reload.delivery_status
  end
end
