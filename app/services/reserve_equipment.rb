class ReserveEquipment
  def self.call(actor, request_id)
    Workflow.run do
      Workflow.authorize!(actor, "distribution.manage")
      request = EquipmentRequest.find(request_id)
      raise Workflow::Error, "Approve the request first." unless request.status == "approved"
      request.request_items.each do |line|
        next if request.reservations.exists?(equipment_id: line.equipment_id, status: %w[active fulfilled])
        Reservation.create!(request_item_id: line.id, request_id: request.id, equipment_id: line.equipment_id, recipient_id: request.recipient_id, reserved_by: actor.id)
      end
      Audit.record!(actor, "request.reserved", request)
      request
    end
  end
end
