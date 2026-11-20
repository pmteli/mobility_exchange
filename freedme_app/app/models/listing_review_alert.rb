# FR006 / FR018: a durable, deduplicated alert per staff account and submitted revision.
class ListingReviewAlert < ApplicationRecord
  self.table_name = "freedme.listing_review_alerts"
  belongs_to :account
  belongs_to :revision, class_name: "ListingRevision"

  def self.enqueue!(revision)
    Account.where(status: "active", id: AccountRole.where(role: "moderator").select(:account_id)).find_each do |account|
      create_or_find_by!(account_id: account.id, revision_id: revision.id)
    end
  end

  def self.review_url(listing_id)
    origin = ENV.fetch("SMS_LINK_BASE_URL", Rails.env.production? ? "https://www.freedme.org" : "http://localhost:3001").delete_suffix("/")
    "#{origin}/moderator/listings/#{listing_id}"
  end
end
