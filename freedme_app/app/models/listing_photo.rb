# PostgreSQL v0.2 owns constraints, lifecycle triggers and UUID defaults.
class ListingPhoto < ApplicationRecord
  self.table_name = "freedme.listing_photos"
  self.primary_key = "id"
  belongs_to :revision, class_name: "ListingRevision", foreign_key: "revision_id", primary_key: "id", optional: false
end
