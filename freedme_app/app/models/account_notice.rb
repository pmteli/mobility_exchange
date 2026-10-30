# PostgreSQL v0.2 owns constraints, lifecycle triggers and UUID defaults.
class AccountNotice < ApplicationRecord
  self.table_name = "freedme.account_notices"
  self.primary_key = "id"
  belongs_to :account, class_name: "Account", foreign_key: "account_id", primary_key: "id", optional: false
  belongs_to :exchange, class_name: "Exchange", foreign_key: "exchange_id", primary_key: "id", optional: true
  belongs_to :listing, class_name: "Listing", foreign_key: "listing_id", primary_key: "id", optional: true
end
