class ShiftSignup < MobilityRecord
  self.table_name = "mobility_exchange.shift_signups"
  self.primary_key = ["shift_id", "volunteer_id"]
end
