# PostgreSQL v0.2 owns constraints, lifecycle triggers and UUID defaults.
class ActionToken < ApplicationRecord
  self.table_name = "freedme.action_tokens"
  self.primary_key = "id"
  belongs_to :account, class_name: "Account", foreign_key: "account_id", primary_key: "id", optional: true
  belongs_to :exchange, class_name: "Exchange", foreign_key: "exchange_id", primary_key: "id", optional: true
  belongs_to :case, class_name: "Case", foreign_key: "case_id", primary_key: "id", optional: true
end
