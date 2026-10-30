# PostgreSQL v0.2 owns constraints, lifecycle triggers and UUID defaults.
class RequestIntent < ApplicationRecord
  self.table_name = "freedme.request_intents"
  self.primary_key = "id"
  belongs_to :listing, class_name: "Listing", foreign_key: "listing_id", primary_key: "id", optional: false
  belongs_to :requester, class_name: "Account", foreign_key: "requester_id", primary_key: "id", optional: false
  belongs_to :evidence, class_name: "IdentityEvidence", foreign_key: "evidence_id", primary_key: "id", optional: true
  belongs_to :exchange, class_name: "Exchange", foreign_key: "exchange_id", primary_key: "id", optional: true
end
