class SubmitRequest
  def self.call(actor, equipment_id, contact)
    Workflow.run do
      item = Equipment.visible.find(equipment_id)
      recipient = Recipient.find_or_initialize_by(user_id: actor.id)
      recipient.assign_attributes(contact.slice(:phone, :address_line1, :city, :region, :postal_code))
      recipient.assign_attributes(first_name: actor.first_name, last_name: actor.last_name, email: actor.email)
      recipient.save!
      request = EquipmentRequest.create!(reference_number: Workflow.reference("REQ"), recipient_id: recipient.id, requested_by: actor.id)
      RequestItem.create!(request_id: request.id, equipment_id: item.id)
      Audit.record!(actor, "request.submitted", request)
      request
    end
  end
end
