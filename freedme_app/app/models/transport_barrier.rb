# PostgreSQL v0.2 owns constraints, lifecycle triggers and UUID defaults.
class TransportBarrier < ApplicationRecord
  self.table_name = "freedme.transport_barriers"
  self.primary_key = "id"
  belongs_to :exchange, class_name: "Exchange", foreign_key: "exchange_id", primary_key: "id", optional: false
  belongs_to :reported_by, class_name: "Account", foreign_key: "reported_by", primary_key: "id", optional: false
  belongs_to :resource, class_name: "Resource", foreign_key: "resource_id", primary_key: "id", optional: true
end
