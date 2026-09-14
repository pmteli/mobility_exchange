class EquipmentRequest < MobilityRecord
  self.table_name = "mobility_exchange.equipment_requests"
  self.primary_key = "id"
  belongs_to :recipient
  has_many :request_items, foreign_key: :request_id
  has_many :reservations, foreign_key: :request_id
  has_many :signed_waivers, foreign_key: :request_id

end
