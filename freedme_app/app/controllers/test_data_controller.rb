# Local inspection; hosted access requires an authenticated administrator.
class TestDataController < ApplicationController
  before_action :require_hosted_administrator

  def index
    return head :not_found unless Journeys::Support.enabled?
    response.headers["Cache-Control"] = "no-store"
    @accounts = Account.where(id: (1..5).map { |n| "019a0000-0000-7000-8000-#{format('%012d', n)}" }).order(:display_name)
    @mobile_numbers = AccountContact.where(account_id: @accounts.select(:id), kind: "mobile", revoked_at: nil).to_h do |contact|
      [contact.account_id, Journeys::Support.decrypt(contact.value_ciphertext)]
    end
    @listings = Listing.where(donor_id: @accounts.select(:id)).includes(:donor).newest_first
    @messages = SimulatedSmsMessage.order(created_at: :desc).limit(100)
  end

  private
  def require_hosted_administrator
    return unless Rails.configuration.x.hosted_demo == true
    response.headers["Cache-Control"] = "no-store"
    unless current_account
      redirect_to sign_in_path
      return
    end
    head :forbidden unless AccountRole.exists?(account_id: current_account.id, role: "administrator")
  end

end
