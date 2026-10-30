# PostgreSQL v0.2 owns constraints, lifecycle triggers and UUID defaults.
class PolicyVersion < ApplicationRecord
  self.table_name = "freedme.policy_versions"
  self.primary_key = "id"
  belongs_to :approved_by_account, class_name: "Account", foreign_key: "approved_by", primary_key: "id", optional: true
end
