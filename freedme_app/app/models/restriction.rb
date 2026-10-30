# PostgreSQL v0.2 owns constraints, lifecycle triggers and UUID defaults.
class Restriction < ApplicationRecord
  self.table_name = "freedme.restrictions"
  self.primary_key = "id"
  belongs_to :listing, class_name: "Listing", foreign_key: "listing_id", primary_key: "id", optional: true
  belongs_to :account, class_name: "Account", foreign_key: "account_id", primary_key: "id", optional: true
  belongs_to :case, class_name: "Case", foreign_key: "case_id", primary_key: "id", optional: true
  belongs_to :applied_by, class_name: "Account", foreign_key: "applied_by", primary_key: "id", optional: false
  belongs_to :released_by, class_name: "Account", foreign_key: "released_by", primary_key: "id", optional: true
end
