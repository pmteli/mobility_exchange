# PostgreSQL v0.2 owns constraints, lifecycle triggers and UUID defaults.
class Agreement < ApplicationRecord
  self.table_name = "freedme.agreements"
  self.primary_key = "id"
  belongs_to :exchange, class_name: "Exchange", foreign_key: "exchange_id", primary_key: "id", optional: false
  belongs_to :terms_policy, class_name: "PolicyVersion", foreign_key: "terms_policy_id", primary_key: "id", optional: false
  belongs_to :accepted_by, class_name: "Account", foreign_key: "accepted_by", primary_key: "id", optional: false
end
