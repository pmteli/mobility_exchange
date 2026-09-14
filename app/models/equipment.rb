class Equipment < MobilityRecord
  self.table_name = "mobility_exchange.equipment"
  self.primary_key = "id"
  belongs_to :equipment_type, foreign_key: :type_id
  belongs_to :location
  has_many :processing_events
  has_many :equipment_status_histories, class_name: "EquipmentStatusHistory"
  validates :name, :inventory_number, :condition, :location_id, :type_id, presence: true
  scope :visible, -> { where(status_code: "available", archived_at: nil) }

end
