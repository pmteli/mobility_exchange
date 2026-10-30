# Development/test inbox only; never represents a provider delivery receipt.
class SimulatedSmsMessage < ApplicationRecord
  self.table_name = "freedme.simulated_sms_messages"
  self.primary_key = "id"
end
