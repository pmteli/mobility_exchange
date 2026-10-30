# PostgreSQL v0.2 owns constraints, lifecycle triggers and UUID defaults.
class Listing < ApplicationRecord
  self.table_name = "freedme.listings"
  self.primary_key = "id"
  belongs_to :donor, class_name: "Account", foreign_key: "donor_id", primary_key: "id", optional: false
  has_many :revisions, class_name: "ListingRevision"
  has_many :exchanges
  scope :newest_first, -> { order(created_at: :desc, id: :desc) }
end
