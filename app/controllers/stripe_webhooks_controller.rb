class StripeWebhooksController < ActionController::Base
  skip_forgery_protection
  def create
    return head :service_unavailable unless DonationCheckout.configured?
    event = Stripe::Webhook.construct_event(request.raw_post, request.headers["Stripe-Signature"], ENV.fetch("STRIPE_WEBHOOK_SECRET"))
    return head :bad_request unless event.livemode == false
    if %w[checkout.session.completed checkout.session.expired checkout.session.async_payment_succeeded].include?(event.type)
      checkout = event.data.object
      # Ignore checkout sessions belonging to other integrations in the same account.
      if checkout.metadata["money_donation_id"].present?
        DonationCheckout.reconcile(checkout)
      end
    end
    head :ok
  rescue JSON::ParserError, Stripe::SignatureVerificationError
    head :bad_request
  rescue ActiveRecord::RecordNotFound, Workflow::Error
    # A webhook may arrive before the checkout ID is committed; let Stripe retry.
    head :service_unavailable
  end
end
