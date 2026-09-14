class EquipmentFile < MobilityRecord
  self.table_name = "mobility_exchange.equipment_files"
  self.primary_key = ["equipment_id", "file_id"]
end
