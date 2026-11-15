require "test_helper"
require Rails.root.join("db/seeds/journeys")

class TwilioIntegrationTest < ActiveSupport::TestCase
  setup do
    @old = ENV.to_h.slice("SMS_PROVIDER", "FREEDME_RECORDING_MODE")
    ENV["SMS_PROVIDER"] = "twilio"
    ENV.delete("FREEDME_RECORDING_MODE")
    load Rails.root.join("db/seeds.rb")
    JourneySeeds.load!
    @account = Account.find(JourneySeeds.id(1))
    @phone = "+15105550101"
  end
  teardown do
    %w[SMS_PROVIDER FREEDME_RECORDING_MODE].each { |k| @old.key?(k) ? ENV[k] = @old[k] : ENV.delete(k) }
  end
  def enqueue(key = "test-message")
    Integrations::SmsGateway.new.deliver(to: @phone, template: "listing_published", parameters: {item_title: "Walker"}, idempotency_key: key)
  end
  test "live sign in uses Verify and consumes a valid challenge once" do
    fake = Object.new
    fake.define_singleton_method(:start_verification) { |phone| "VEtest" }
    fake.define_singleton_method(:check_verification) { |sid, code| sid == "VEtest" && code == "123456" }
    begin
      pending = nil
      assert_no_difference "SimulatedSmsMessage.count" do
        pending = Journeys::Authentication.start!(mobile: @phone, client: fake)
      end
      assert_equal "twilio", AuthChallenge.find(pending["challenge_id"]).provider
      assert_equal @account, Journeys::Authentication.verify!(pending, "123456", client: fake)
      assert_raises(Journeys::Error) { Journeys::Authentication.verify!(pending, "123456", client: fake) }
    end
  end
  test "Verify failure never creates an account" do
    fake = Object.new
    fake.define_singleton_method(:start_verification) { |phone| "VEtest" }
    fake.define_singleton_method(:check_verification) { |sid, code| false }
    begin
      pending = Journeys::Authentication.start!(mobile: "+15105550199", name: "Test", locality: "Fremont", registration: true, client: fake)
      assert_no_difference "Account.count" do
        3.times { assert_raises(Journeys::Error) { Journeys::Authentication.verify!(pending, "111111", client: fake) } }
      end
      assert AuthChallenge.find(pending["challenge_id"]).invalidated_at
    end
  end
  test "outbox is deduplicated and encrypted" do
    assert_difference "SmsDelivery.count", 1 do
      2.times { enqueue }
    end
    row = enqueue
    refute_includes row.body_ciphertext, "Walker"
    assert_includes Journeys::Support.decrypt(row.body_ciphertext), "Walker"
    assert_includes Journeys::Support.decrypt(row.body_ciphertext), "STOP"
  end
  test "consent is checked at dispatch and opted-out messages suppressed" do
    row = enqueue
    Integrations::SmsDispatcher.run!(client: Object.new)
    assert_equal "suppressed", row.reload.state
  end
  test "consented delivery is sent only once" do
    Integrations::SmsConsent.grant!(@account, key: "consent-test")
    row = enqueue
    fake = Object.new
    fake.define_singleton_method(:send_message) { |**args| "SMtest" }
    Integrations::SmsDispatcher.run!(client: fake)
    Integrations::SmsDispatcher.run!(client: Object.new)
    assert_equal "accepted", row.reload.state
    assert_equal "SMtest", row.provider_sid
  end
  test "uncertain provider failure does not automatically resend" do
    Integrations::SmsConsent.grant!(@account, key: "consent-test")
    row = enqueue
    fake = Object.new
    fake.define_singleton_method(:send_message) { |**args| raise Integrations::TwilioClient::DeliveryError }
    Integrations::SmsDispatcher.run!(client: fake)
    Integrations::SmsDispatcher.run!(client: Object.new)
    assert_equal "failed", row.reload.state
  end
  test "recordings remain simulated even with live provider setting" do
    ENV["FREEDME_RECORDING_MODE"] = "true"
    refute Integrations::TwilioClient.live?
    assert_difference "SimulatedSmsMessage.count", 1 do
      enqueue
    end
  end
  test "live mode rejects pending simulated OTP" do
    challenge = AuthChallenge.new(code_digest: Journeys::Support.digest("123456"), provider: "simulated")
    refute Journeys::Authentication.valid_code?(challenge, "123456")
  end
end

class TwilioVerifyTest < ActiveSupport::TestCase
  test "Verify API request uses verification SID and only accepts approved status" do
    client = Integrations::TwilioClient.new
    calls = []
    client.define_singleton_method(:verify_sid) { "VAservice" }
    client.define_singleton_method(:post) do |host, path, fields|
      calls << [host, path, fields]
      {"sid" => "VEchallenge", "status" => fields[:Code] == "123456" ? "approved" : "pending"}
    end
    assert_equal "VEchallenge", client.start_verification("+15105550101")
    assert client.check_verification("VEchallenge", "123456")
    refute client.check_verification("VEchallenge", "000000")
    assert_equal({VerificationSid: "VEchallenge", Code: "123456"}, calls[1][2])
  end
end
