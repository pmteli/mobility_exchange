# PostgreSQL v0.2 owns constraints, lifecycle triggers and UUID defaults.
class ExchangeEvent < ApplicationRecord
  self.table_name = "freedme.exchange_events"
  self.primary_key = "id"
  belongs_to :exchange, class_name: "Exchange", foreign_key: "exchange_id", primary_key: "id", optional: false
  belongs_to :actor, class_name: "Account", foreign_key: "actor_id", primary_key: "id", optional: true
end
