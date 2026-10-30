# PostgreSQL v0.2 owns constraints, lifecycle triggers and UUID defaults.
class PilotControl < ApplicationRecord
  self.table_name = "freedme.pilot_controls"
  self.primary_key = "singleton"
  belongs_to :privacy_policy, class_name: "PolicyVersion", foreign_key: "privacy_policy_id", primary_key: "id", optional: true
  belongs_to :loan_policy, class_name: "PolicyVersion", foreign_key: "loan_policy_id", primary_key: "id", optional: true
end
