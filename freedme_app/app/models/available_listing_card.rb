# FR007–008: only database-approved public fields and eligible listings.
class AvailableListingCard < ApplicationRecord
  self.table_name = "freedme.available_listing_cards"
  self.primary_key = "id"

  def readonly?
    true
  end
end
