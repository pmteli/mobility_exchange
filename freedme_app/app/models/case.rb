# PostgreSQL v0.2 owns constraints, lifecycle triggers and UUID defaults.
class Case < ApplicationRecord
  self.table_name = "freedme.cases"
  self.primary_key = "id"
  belongs_to :reporter, class_name: "Account", foreign_key: "reporter_id", primary_key: "id", optional: true
  belongs_to :listing, class_name: "Listing", foreign_key: "listing_id", primary_key: "id", optional: true
  belongs_to :exchange, class_name: "Exchange", foreign_key: "exchange_id", primary_key: "id", optional: true
  belongs_to :owner, class_name: "Account", foreign_key: "owner_id", primary_key: "id", optional: false
end
