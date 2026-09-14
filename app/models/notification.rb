class Notification < MobilityRecord
  self.table_name = "mobility_exchange.notification_outbox"
  self.primary_key = "id"
end
