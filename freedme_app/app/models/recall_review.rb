# PostgreSQL v0.2 owns constraints, lifecycle triggers and UUID defaults.
class RecallReview < ApplicationRecord
  self.table_name = "freedme.recall_reviews"
  self.primary_key = "id"
  belongs_to :policy, class_name: "PolicyVersion", foreign_key: "policy_id", primary_key: "id", optional: false
  belongs_to :revision, class_name: "ListingRevision", foreign_key: "revision_id", primary_key: "id", optional: false
  belongs_to :reviewer, class_name: "Account", foreign_key: "reviewer_id", primary_key: "id", optional: false
end
