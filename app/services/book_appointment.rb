class BookAppointment
  def self.call(actor, record, slot_id)
    Workflow.run do
      record.reload
      field = record.is_a?(EquipmentRequest) ? :requested_by : :submitted_by
      Workflow.owner!(actor, record, field)
      raise Workflow::Error, "The team must approve this submission first." unless record.status == "approved"
      request_kind = record.is_a?(EquipmentRequest)
      signed = request_kind ? record.signed_waivers.exists? : record.signed_donor_certifications.exists?
      raise Workflow::Error, "Sign the required document first." unless signed
      slot = AppointmentSlot.where(cancelled_at: nil).where("starts_at > ?", Time.current).find(slot_id)
      location = Location.find(slot.location_id)
      raise Workflow::Error, "This location is unavailable." unless location.status == "active" && (request_kind ? location.pickup_enabled : location.dropoff_enabled)
      if request_kind
        locations = Equipment.where(id: record.reservations.where(status: "active").select(:equipment_id)).distinct.pluck(:location_id)
        raise Workflow::Error, "Reserve the equipment at this pickup location first." unless locations == [slot.location_id]
      end
      attrs = request_kind ? { request_id: record.id } : { intake_id: record.id }
      appointment = Appointment.create!(attrs.merge(slot_id: slot.id))
      record.update!(status: "scheduled") unless request_kind
      Audit.record!(actor, "appointment.booked", appointment)
      appointment
    end
  end
end
