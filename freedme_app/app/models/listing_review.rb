# PostgreSQL v0.2 owns constraints, lifecycle triggers and UUID defaults.
class ListingReview < ApplicationRecord
  self.table_name = "freedme.listing_reviews"
  self.primary_key = "id"
  belongs_to :revision, class_name: "ListingRevision", foreign_key: "revision_id", primary_key: "id", optional: false
  belongs_to :reviewer, class_name: "Account", foreign_key: "reviewer_id", primary_key: "id", optional: false
end
