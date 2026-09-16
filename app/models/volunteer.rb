class Volunteer < MobilityRecord
  self.table_name = "mobility_exchange.volunteers"
  self.primary_key = "user_id"
  belongs_to :user, foreign_key: :user_id

end
