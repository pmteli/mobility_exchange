# PostgreSQL v0.2 owns constraints, lifecycle triggers and UUID defaults.
class PrivateMessage < ApplicationRecord
  self.table_name = "freedme.private_messages"
  self.primary_key = "id"
  belongs_to :exchange, class_name: "Exchange", foreign_key: "exchange_id", primary_key: "id", optional: false
  belongs_to :sender, class_name: "Account", foreign_key: "sender_id", primary_key: "id", optional: false
  belongs_to :recipient, class_name: "Account", foreign_key: "recipient_id", primary_key: "id", optional: false
  belongs_to :messaging_policy, class_name: "PolicyVersion", foreign_key: "messaging_policy_id", primary_key: "id", optional: true
end
