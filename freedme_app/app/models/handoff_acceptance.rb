# PostgreSQL v0.2 owns constraints, lifecycle triggers and UUID defaults.
class HandoffAcceptance < ApplicationRecord
  self.table_name = "freedme.handoff_acceptances"
  self.primary_key = "proposal_id"
  belongs_to :accepted_by_account, class_name: "Account", foreign_key: "accepted_by", primary_key: "id", optional: false
end
