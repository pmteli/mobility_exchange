class Location < MobilityRecord
  self.table_name = "mobility_exchange.locations"
  self.primary_key = "id"
  validates :name, presence: true
  validate do
    errors.add(:timezone, "must be a recognized timezone") unless ActiveSupport::TimeZone[timezone]
  end
end
