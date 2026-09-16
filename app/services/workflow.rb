class Workflow
  class Error < StandardError; end
  def self.run(&operation)
    MobilityTransaction.call(&operation)
  rescue ActiveRecord::StatementInvalid => error
    if error.cause.respond_to?(:result) && %w[23514 23503].include?(error.cause.result.error_field(PG::Result::PG_DIAG_SQLSTATE))
      raise Error, "This action conflicts with a workflow rule. Check the status, capacity, and required evidence, then try again."
    end
    raise
  end
  def self.authorize!(actor, permission)
    raise Error, "You do not have permission for this action." unless User.find(actor.id).allowed?(permission)
  end
  def self.owner!(actor, record, field)
    raise ActiveRecord::RecordNotFound unless record.public_send(field) == actor.id
  end
  def self.reference(prefix)
    "#{prefix}-#{SecureRandom.hex(5).upcase}"
  end
end
