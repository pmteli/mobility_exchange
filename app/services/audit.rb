class Audit
  def self.record!(actor, action, record)
    AuditEvent.create!(actor_kind: "user", actor_user_id: actor.id,
      action: action, entity_type: record.class.name, entity_id: record.id.to_s)
  end
end
