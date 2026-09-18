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
      Notification.create!(deduplication_key: "request-confirmation:#{request.id}", recipient_user_id: actor.id,
        channel: "email", destination: actor.email, template_key: "equipment_request_confirmation",
        payload_json: { first_name: actor.first_name, request_id: request.id, reference_number: request.reference_number,
          equipment_name: item.name, inventory_number: item.inventory_number, equipment_type: item.equipment_type.name,
          category: item.equipment_type.equipment_category.name, condition: item.condition })
      Audit.record!(actor, "request.submitted", request)
      request
    end
  end
end
