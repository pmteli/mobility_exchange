require "test_helper"
class MoneyDonationsTest < ActionDispatch::IntegrationTest
  setup do
    @old_key, @old_webhook = ENV["STRIPE_SECRET_KEY"], ENV["STRIPE_WEBHOOK_SECRET"]
    ENV["STRIPE_SECRET_KEY"] = "sk_test_example"
    ENV["STRIPE_WEBHOOK_SECRET"] = "whsec_example"
    @user = create_user
    post session_path, params: { email: @user.email, password: "correct horse battery staple" }
  end
  teardown do
    ENV["STRIPE_SECRET_KEY"], ENV["STRIPE_WEBHOOK_SECRET"] = @old_key, @old_webhook
  end

  def donation
    @donation ||= Workflow.run { MoneyDonation.create!(user: @user, email: @user.email, request_key: SecureRandom.uuid, amount_cents: 2500, stripe_session_id: "cs_test_#{SecureRandom.hex(10)}") }
  end

  def checkout(record = donation, **overrides)
    Stripe::StripeObject.construct_from({ id: record.stripe_session_id, object: "checkout.session", livemode: false,
      mode: "payment", currency: "usd", amount_total: record.amount_cents, client_reference_id: record.id,
      metadata: { money_donation_id: record.id }, payment_status: "paid", status: "complete",
      payment_intent: "pi_#{record.id}", url: nil }.merge(overrides))
  end

  def send_event(object, type: "checkout.session.completed", signed: true)
    payload = { id: "evt_#{SecureRandom.hex(8)}", object: "event", livemode: false, type: type, data: { object: object.to_hash } }.to_json
    timestamp = Time.now.to_i
    signature = OpenSSL::HMAC.hexdigest("SHA256", ENV.fetch("STRIPE_WEBHOOK_SECRET"), "#{timestamp}.#{payload}")
    post "/webhooks/stripe", params: payload, headers: { "CONTENT_TYPE" => "application/json", "Stripe-Signature" => "t=#{timestamp},v1=#{signed ? signature : 'invalid'}" }
  end

  test "preset amounts and exact custom cents reject malformed or out of range amounts" do
    MoneyDonation::PRESETS.each { |n| assert_equal n * 100, MoneyDonation.parse_amount(n.to_s, nil) }
    assert_equal 1234, MoneyDonation.parse_amount("custom", "12.34")
    assert_equal 100, MoneyDonation.parse_amount("custom", "1")
    ["0", "-1", "NaN", "1e3", "1.001", "10000.01", "100000", ""].each do |value|
      assert_raises(Workflow::Error) { MoneyDonation.parse_amount("custom", value) }
    end
    assert_raises(Workflow::Error) { MoneyDonation.parse_amount("123", "123") }
  end

  test "form renders presets and validation inline without creating a payment" do
    get new_money_donation_path
    assert_response :success
    assert_select 'input[type=radio][name=amount]', count: 6
    assert_select 'input[type=submit][disabled]', count: 0
    assert_no_difference "MoneyDonation.count" do
      post money_donations_path, params: { amount: "custom", custom_amount: "-1", checkout_token: DonationCheckout.token(@user) }
    end
    assert_response :unprocessable_entity
    assert_select 'h1 + .signup-error-summary[role=alert]'
  end

  test "disabled and live credentials cannot create checkout" do
    [nil, "sk_live_forbidden"].each do |key|
      ENV["STRIPE_SECRET_KEY"] = key
      get new_money_donation_path
      assert_select 'input[type=submit][disabled]', count: 1
      assert_no_difference "MoneyDonation.count" do
        post money_donations_path, params: { amount: "25", checkout_token: DonationCheckout.token(@user) }
      end
      assert_response :service_unavailable
    end
  end

  test "signed notifications confirm once and expired events cannot regress paid status" do
    object = checkout
    send_event(object, signed: false)
    assert_response :bad_request
    assert_equal "pending", donation.reload.status
    send_event(object)
    assert_response :ok
    first_paid_at = donation.reload.paid_at
    assert_equal "paid", donation.status
    send_event(object)
    assert_response :ok
    assert_equal first_paid_at, donation.reload.paid_at
    send_event(checkout(payment_status: "unpaid", status: "expired"), type: "checkout.session.expired")
    assert_response :ok
    assert_equal "paid", donation.reload.status
  end

  test "amount currency mode and ownership mismatches cannot mark paid" do
    [{ amount_total: 100 }, { currency: "eur" }, { livemode: true }, { client_reference_id: "other" }, { metadata: { money_donation_id: "other" } }, { payment_intent: nil }].each do |fields|
      send_event(checkout(**fields))
      assert_response :service_unavailable
      assert_equal "pending", donation.reload.status
    end
    send_event(checkout(payment_status: "unpaid", status: "open"))
    assert_response :ok
    assert_equal "pending", donation.reload.status
  end

  test "return URL does not confirm payment and another user cannot see donation" do
    record = donation
    ENV.delete("STRIPE_SECRET_KEY")
    get money_donation_path(record, success: "1")
    assert_response :success
    assert_equal "pending", record.reload.status
    assert_includes response.body, "not yet confirmed"
    other = create_user
    delete session_path
    post session_path, params: { email: other.email, password: "correct horse battery staple" }
    get money_donation_path(record)
    assert_response :not_found
    delete session_path
    get new_money_donation_path
    assert_redirected_to new_session_path
  end

  test "successful checkout redirects to Stripe and repeated submit reuses the session" do
    calls = []
    sessions = Object.new
    sessions.define_singleton_method(:create) do |params, options|
      calls << options
      Stripe::StripeObject.construct_from({ id: "cs_test_#{SecureRandom.hex(10)}", livemode: false,
        mode: "payment", currency: "usd", amount_total: params[:line_items][0][:price_data][:unit_amount],
        client_reference_id: params[:client_reference_id], metadata: params[:metadata],
        payment_status: "unpaid", status: "open", payment_intent: nil,
        url: "https://checkout.stripe.com/c/pay/test-example" })
    end
    sessions.define_singleton_method(:retrieve) do |id|
      record = MoneyDonation.find_by!(stripe_session_id: id)
      Stripe::StripeObject.construct_from({ id: id, livemode: false, mode: "payment", currency: "usd",
        amount_total: record.amount_cents, client_reference_id: record.id, metadata: { money_donation_id: record.id },
        payment_status: "unpaid", status: "open", payment_intent: nil,
        url: "https://checkout.stripe.com/c/pay/test-example" })
    end
    api = Struct.new(:v1).new(Struct.new(:checkout).new(Struct.new(:sessions).new(sessions)))
    original = DonationCheckout.method(:client)
    DonationCheckout.define_singleton_method(:client) { api }
    token = DonationCheckout.token(@user)
    2.times do
      post money_donations_path, params: { amount: "custom", custom_amount: "12.34", checkout_token: token }
      assert_redirected_to "https://checkout.stripe.com/c/pay/test-example"
      assert_response :see_other
    end
    assert_equal 1, calls.size
    record = MoneyDonation.find_by!(user_id: @user.id)
    assert_equal 1234, record.amount_cents
    assert_equal "pending", record.status
    send_event(checkout(record, payment_status: "unpaid", status: "expired"), type: "checkout.session.expired")
    assert_response :ok
    assert_equal "expired", record.reload.status
  ensure
    DonationCheckout.define_singleton_method(:client, original) if original
  end

  test "checkout retries reuse record and Stripe idempotency key outside transactions" do
    calls = []
    sessions = Object.new
    sessions.define_singleton_method(:create) do |params, options|
      raise "network inside database transaction" if ActiveRecord::Base.connection.transaction_open?
      calls << [params, options]
      raise Stripe::APIConnectionError, "simulated timeout"
    end
    api = Struct.new(:v1).new(Struct.new(:checkout).new(Struct.new(:sessions).new(sessions)))
    original = DonationCheckout.method(:client)
    DonationCheckout.define_singleton_method(:client) { api }
    token = DonationCheckout.token(@user)
    2.times do
      post money_donations_path, params: { amount: "25", checkout_token: token }
      assert_response :service_unavailable
    end
    assert_equal 1, MoneyDonation.where(user_id: @user.id).count
    assert_equal calls.first, calls.last
    assert_equal 2500, calls.first[0][:line_items][0][:price_data][:unit_amount]
    assert_equal ["card"], calls.first[0][:payment_method_types]
    assert_raises(Workflow::Error) { DonationCheckout.start(user: @user, amount_cents: 5000, token: token) }
    assert_raises(Workflow::Error) { DonationCheckout.start(user: create_user, amount_cents: 2500, token: token) }
  ensure
    DonationCheckout.define_singleton_method(:client, original) if original
  end
end
