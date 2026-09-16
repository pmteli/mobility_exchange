class IntakeItemFile < MobilityRecord
  self.table_name = "mobility_exchange.intake_item_files"
  self.primary_key = ["intake_item_id", "file_id"]
  belongs_to :intake_item
  belongs_to :stored_file, foreign_key: :file_id
end
