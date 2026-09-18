class MoneyDonationsController < ApplicationController
  before_action :require_login
  rate_limit to: 10, within: 5.minutes, only: :create, with: -> { form_error("Please wait a few minutes before trying again.", :too_many_requests) }

  def index
    @donations = MoneyDonation.where(user_id: current_user.id).order(created_at: :desc).limit(100)
  end

  def new
    @checkout_token = DonationCheckout.token(current_user)
  end

  def create
    cents = MoneyDonation.parse_amount(params[:amount], params[:custom_amount])
    url = DonationCheckout.start(user: current_user, amount_cents: cents, token: params[:checkout_token])
    redirect_to url, allow_other_host: true, status: :see_other
  rescue Workflow::Error => error
    form_error(error.message)
  rescue DonationCheckout::Unavailable => error
    form_error(error.message, :service_unavailable)
  rescue Stripe::StripeError => error
    Rails.logger.warn("Donation checkout failed: #{error.class}")
    form_error("We could not connect to checkout. Try again using this form; your checkout will not be duplicated.", :service_unavailable)
  end

  def show
    @donation = MoneyDonation.where(user_id: current_user.id).find(params[:id])
    if @donation.status == "pending" && @donation.stripe_session_id && DonationCheckout.configured?
      DonationCheckout.reconcile(DonationCheckout.client.v1.checkout.sessions.retrieve(@donation.stripe_session_id))
      @donation.reload
    end
  rescue Stripe::StripeError, DonationCheckout::Unavailable
    @status_notice = "Payment status is temporarily unavailable. Please check back shortly."
  end

  private
  def form_error(message, status = :unprocessable_entity)
    @error = message
    @checkout_token = params[:checkout_token].presence || DonationCheckout.token(current_user)
    render :new, status: status
  end
end
