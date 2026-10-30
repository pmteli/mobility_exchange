# PostgreSQL v0.2 owns constraints, lifecycle triggers and UUID defaults.
class ExchangeDisplayPreference < ApplicationRecord
  self.table_name = "freedme.exchange_display_preferences"
  self.primary_key = [ "exchange_id", "account_id" ]
  belongs_to :exchange, class_name: "Exchange", foreign_key: "exchange_id", primary_key: "id", optional: false
  belongs_to :account, class_name: "Account", foreign_key: "account_id", primary_key: "id", optional: false
  belongs_to :replaced_by_exchange, class_name: "Exchange", foreign_key: "replaced_by_exchange_id", primary_key: "id", optional: true
end
