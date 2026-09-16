class EquipmentType < MobilityRecord
  self.table_name = "mobility_exchange.equipment_types"
  self.primary_key = "id"
  belongs_to :equipment_category, foreign_key: :category_id

end
