class Reservation < MobilityRecord
  self.table_name = "mobility_exchange.reservations"
  self.primary_key = "id"
  belongs_to :equipment

end
