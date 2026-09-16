class IntakeItemFile < MobilityRecord
  self.table_name = "mobility_exchange.intake_item_files"
  self.primary_key = ["intake_item_id", "file_id"]
end
