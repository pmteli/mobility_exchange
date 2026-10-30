# FR043: trusted worker time; the database enforces one task per reservation.
# Not scheduled automatically. Use a durable queue before production deployment.
class HandoffFollowupJob < ApplicationJob
  queue_as :maintenance

  def perform
    ApplicationRecord.connection.execute("SELECT freedme.enqueue_handoff_followups()")
  end
end
