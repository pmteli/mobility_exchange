class VolunteerShift < MobilityRecord
  include ScheduleValidations
  self.table_name = "mobility_exchange.volunteer_shifts"
  self.primary_key = "id"
  belongs_to :location
  has_many :shift_signups, foreign_key: :shift_id

end
