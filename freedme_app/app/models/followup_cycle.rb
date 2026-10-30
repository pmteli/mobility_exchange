# PostgreSQL v0.2 owns constraints, lifecycle triggers and UUID defaults.
class FollowupCycle < ApplicationRecord
  self.table_name = "freedme.followup_cycles"
  self.primary_key = "id"
  belongs_to :exchange, class_name: "Exchange", foreign_key: "exchange_id", primary_key: "id", optional: false
end
