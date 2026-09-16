class IntakeItem < MobilityRecord
  self.table_name = "mobility_exchange.intake_items"
  self.primary_key = "id"
  belongs_to :equipment_type, foreign_key: :type_id

end
