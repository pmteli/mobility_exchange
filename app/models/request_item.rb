class RequestItem < MobilityRecord
  self.table_name = "mobility_exchange.request_items"
  self.primary_key = "id"
  belongs_to :equipment

end
