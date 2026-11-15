class SmsDelivery < ApplicationRecord
  self.table_name = "freedme.sms_deliveries"
  def body
    Journeys::Support.decrypt(body_ciphertext)
  end
end
