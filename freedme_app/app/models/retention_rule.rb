# PostgreSQL v0.2 owns constraints, lifecycle triggers and UUID defaults.
class RetentionRule < ApplicationRecord
  self.table_name = "freedme.retention_rules"
  self.primary_key = "id"
  belongs_to :policy, class_name: "PolicyVersion", foreign_key: "policy_id", primary_key: "id", optional: false
end
