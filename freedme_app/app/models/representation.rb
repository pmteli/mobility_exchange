# PostgreSQL v0.2 owns constraints, lifecycle triggers and UUID defaults.
class Representation < ApplicationRecord
  self.table_name = "freedme.representations"
  self.primary_key = "id"
  belongs_to :representative, class_name: "Account", foreign_key: "representative_id", primary_key: "id", optional: false
  belongs_to :recipient_account, class_name: "Account", foreign_key: "recipient_account_id", primary_key: "id", optional: true
  belongs_to :authority_policy, class_name: "PolicyVersion", foreign_key: "authority_policy_id", primary_key: "id", optional: false
end
