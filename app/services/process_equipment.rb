class ProcessEquipment
  STEPS = {
    "awaiting_inspection" => ["inspected", "inspection", "passed"],
    "awaiting_sanitization" => ["sanitized", "sanitization", "completed"],
    "needs_repair" => ["awaiting_inspection", "repair", "completed"]
  }.freeze
  def self.call(actor, id, target, notes)
    Workflow.run do
      Workflow.authorize!(actor, "inventory.process")
      equipment = Equipment.find(id)
      raise Workflow::Error, "Add notes describing the work performed." if notes.blank?
      valid = InventoryTransition.exists?(from_status: equipment.status_code, to_status: target)
      raise Workflow::Error, "Choose a valid processing step." unless valid && !%w[reserved distributed].include?(target) && equipment.status_code != "reserved"
      step = STEPS[equipment.status_code]
      if step && step[0] == target
        ProcessingEvent.create!(equipment_id: equipment.id, kind: step[1], outcome: step[2], performed_by: actor.id, performed_at: Time.current, notes: notes)
      end
      if target == "needs_repair"
        ProcessingEvent.create!(equipment_id: equipment.id, kind: "inspection", outcome: "needs_repair", performed_by: actor.id, performed_at: Time.current, notes: notes)
      end
      attributes = { status_code: target, updated_by: actor.id }
      attributes[:disposition_reason] = notes if target == "disposal"
      equipment.update!(attributes)
      Audit.record!(actor, "equipment.#{target}", equipment)
      equipment
    end
  end
end
