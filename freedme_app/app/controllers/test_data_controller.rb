# Local-only read-only inspection. Does not grant staff or member sessions.
class TestDataController < ApplicationController
  def index
    return head :not_found unless Rails.env.development? || Rails.env.test?
    response.headers["Cache-Control"] = "no-store"
    @accounts = Account.where(id: (1..5).map { |n| "019a0000-0000-7000-8000-#{format('%012d', n)}" }).order(:display_name)
    @mobile_numbers = AccountContact.where(account_id: @accounts.select(:id), kind: "mobile", revoked_at: nil).to_h do |contact|
      [contact.account_id, Journeys::Support.decrypt(contact.value_ciphertext)]
    end
    @listings = Listing.where(donor_id: @accounts.select(:id)).includes(:donor).newest_first
    @messages = SimulatedSmsMessage.order(created_at: :desc).limit(100)
  end
end
