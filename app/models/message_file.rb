class MessageFile < MobilityRecord
  self.table_name = "mobility_exchange.message_files"
  self.primary_key = ["message_id", "file_id"]
end
