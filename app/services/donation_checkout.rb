class DonationCheckout
  class Unavailable < StandardError; end

  def self.configured?
    ENV["STRIPE_SECRET_KEY"].to_s.start_with?("sk_test_") && ENV["STRIPE_WEBHOOK_SECRET"].to_s.start_with?("whsec_")
  end

  def self.client
    raise Unavailable, "Card donations are being set up. Please try again later." unless configured?
    Stripe::StripeClient.new(ENV.fetch("STRIPE_SECRET_KEY"))
  end

  def self.token(user)
    Rails.application.message_verifier("money-donation").generate({ "user_id" => user.id, "key" => SecureRandom.uuid }, expires_in: 1.hour)
  end

  def self.start(user:, amount_cents:, token:)
    api = client
    data = Rails.application.message_verifier("money-donation").verified(token)
    raise Workflow::Error, "This form has expired. Reload the page and try again." unless data && data["user_id"] == user.id
    donation = Workflow.run do
      record = MoneyDonation.create_or_find_by!(user_id: user.id, request_key: data.fetch("key")) do |new_record|
        new_record.assign_attributes(amount_cents: amount_cents, email: user.email)
      end
      if record.amount_cents != amount_cents
        raise Workflow::Error, "An amount was already submitted from this form. Start a new donation to change it."
      end
      record
    end
    raise Workflow::Error, "This donation is already paid or expired. Start a new donation." unless donation.status == "pending"
    # Network requests stay outside retryable database transactions. Repeated submissions
    # use the same Stripe idempotency key and the same persisted payment parameters.
    checkout = if donation.stripe_session_id
      api.v1.checkout.sessions.retrieve(donation.stripe_session_id)
    else
      raise Workflow::Error, "This checkout has expired. Start a new donation." if donation.created_at < 23.hours.ago
      api.v1.checkout.sessions.create({
        mode: "payment", payment_method_types: ["card"], submit_type: "donate",
        client_reference_id: donation.id, metadata: { money_donation_id: donation.id },
        customer_email: donation.email,
        line_items: [{ quantity: 1, price_data: { currency: "usd", unit_amount: donation.amount_cents,
          product_data: { name: "Donation to Mobility Exchange" } } }],
        success_url: return_url(donation), cancel_url: return_url(donation) + "?cancelled=1"
      }, { idempotency_key: "money-donation-#{donation.id}" })
    end
    raise Unavailable, "Unable to open test checkout. Please try again." unless checkout.livemode == false
    Workflow.run { donation.reload.update!(stripe_session_id: checkout.id) }
    reconcile(checkout)
    uri = URI.parse(checkout.url.to_s)
    raise Workflow::Error, "This checkout is complete or expired. View your donation history." unless uri.scheme == "https" && uri.host == "checkout.stripe.com"
    checkout.url
  end

  def self.return_url(donation)
    host = ENV.fetch("APP_HOST", "localhost")
    port = ENV.fetch("APP_PORT", "3000").to_i
    Rails.application.routes.url_helpers.money_donation_url(donation, host: host, port: port,
      protocol: Rails.env.production? ? "https" : "http")
  end

  def self.reconcile(checkout)
    Workflow.run do
      donation = MoneyDonation.find_by!(stripe_session_id: checkout.id)
      unless checkout.livemode == false && checkout.mode == "payment" && checkout.currency == donation.currency &&
          checkout.amount_total == donation.amount_cents && checkout.client_reference_id == donation.id &&
          checkout.metadata["money_donation_id"] == donation.id
        raise Workflow::Error, "Payment details did not match the donation."
      end
      if checkout.payment_status == "paid"
        raise Workflow::Error, "Payment reference is missing." if checkout.payment_intent.blank?
        unless donation.status == "paid"
          donation.update!(status: "paid", paid_at: Time.current, stripe_payment_intent_id: checkout.payment_intent)
        end
      elsif checkout.status == "expired" && donation.status == "pending"
        donation.update!(status: "expired")
      end
      donation
    end
  end
end
