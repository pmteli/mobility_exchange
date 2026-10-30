# PostgreSQL v0.2 owns constraints, lifecycle triggers and UUID defaults.
class HandoffProposal < ApplicationRecord
  self.table_name = "freedme.handoff_proposals"
  self.primary_key = "id"
  belongs_to :exchange, class_name: "Exchange", foreign_key: "exchange_id", primary_key: "id", optional: false
  belongs_to :proposed_by_account, class_name: "Account", foreign_key: "proposed_by", primary_key: "id", optional: false
end
