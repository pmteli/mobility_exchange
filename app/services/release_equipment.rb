class ReleaseEquipment
  def self.call(actor, request_id, reservation_id, signature, condition)
    Workflow.authorize!(actor, "distribution.manage")
    raise Workflow::Error, "Capture the recipient's pickup signature and equipment condition." unless signature.to_s.strip.length.between?(2, 150) && condition.present?
    evidence = PrivateEvidence.prepare(JSON.generate(signer: signature.strip, captured_by: actor.id, reservation_id: reservation_id, captured_at: Time.current.iso8601), "pickup-signature.json", "application/json")
    Workflow.run do
      Workflow.authorize!(actor, "distribution.manage")
      request = EquipmentRequest.find(request_id)
      reservation = request.reservations.find(reservation_id)
      waiver = request.signed_waivers.order(signed_at: :desc).first or raise Workflow::Error, "A signed waiver is required."
      appointment = Appointment.find_by(request_id: request.id, status: "booked") or raise Workflow::Error, "Book a pickup appointment first."
      slot = AppointmentSlot.find(appointment.slot_id)
      raise Workflow::Error, "Equipment is at a different pickup location." unless reservation.equipment.location_id == slot.location_id
      release = Distribution.create!(reservation_id: reservation.id, equipment_id: reservation.equipment_id, recipient_id: request.recipient_id, request_id: request.id, waiver_id: waiver.id, appointment_id: appointment.id, released_by: actor.id, released_at: Time.current, pickup_signature_file_id: PrivateEvidence.persist!(evidence, actor).id, condition_at_pickup: condition)
      Audit.record!(actor, "equipment.distributed", release)
      release
    end
  end
end
