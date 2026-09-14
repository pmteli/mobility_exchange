class AppointmentSlot < MobilityRecord
  include ScheduleValidations
  self.table_name = "mobility_exchange.appointment_slots"
  self.primary_key = "id"
  belongs_to :location
  has_many :appointments, foreign_key: :slot_id

end
