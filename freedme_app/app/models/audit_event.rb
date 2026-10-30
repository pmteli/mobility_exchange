# PostgreSQL v0.2 owns constraints, lifecycle triggers and UUID defaults.
class AuditEvent < ApplicationRecord
  self.table_name = "freedme.audit_events"
  self.primary_key = "id"
  belongs_to :actor, class_name: "Account", foreign_key: "actor_id", primary_key: "id", optional: true
end
