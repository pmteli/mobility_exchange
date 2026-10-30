# PostgreSQL v0.2 owns constraints, lifecycle triggers and UUID defaults.
class Account < ApplicationRecord
  self.table_name = "freedme.accounts"
  self.primary_key = "id"
  has_many :listings, foreign_key: :donor_id
  has_many :donor_exchanges, class_name: "Exchange", foreign_key: :donor_id
  has_many :recipient_exchanges, class_name: "Exchange", foreign_key: :requester_id
end
