# PostgreSQL v0.2 owns constraints, lifecycle triggers and UUID defaults.
class ActivityEvent < ApplicationRecord
  self.table_name = "freedme.activity_events"
  self.primary_key = "id"
  belongs_to :account, class_name: "Account", foreign_key: "account_id", primary_key: "id", optional: false
  belongs_to :policy, class_name: "PolicyVersion", foreign_key: "policy_id", primary_key: "id", optional: true
end
