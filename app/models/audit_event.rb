class AuditEvent < MobilityRecord
  self.table_name = "mobility_exchange.audit_events"
  self.primary_key = "id"
end
