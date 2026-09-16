class IntakeItem < MobilityRecord
  self.table_name = "mobility_exchange.intake_items"
  self.primary_key = "id"
  belongs_to :equipment_type, foreign_key: :type_id
  has_many :intake_item_files
  has_many :photos, through: :intake_item_files, source: :stored_file

end
