# PostgreSQL v0.2 owns constraints, lifecycle triggers and UUID defaults.
class GatewayEvent < ApplicationRecord
  self.table_name = "freedme.gateway_events"
  self.primary_key = "id"
  belongs_to :attempt, class_name: "MessageAttempt", foreign_key: "attempt_id", primary_key: "id", optional: true
end
