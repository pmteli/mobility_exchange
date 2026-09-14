# At-least-once delivery: a crash after SMTP accepts mail may cause a duplicate.
class NotificationDelivery
  def self.deliver_one
    lease = Time.current
    record = Workflow.run do
      next_record = Notification.where(channel: "email").where("available_at <= ?", lease).where("status = 'pending' OR (status = 'processing' AND locked_at < ?)", 10.minutes.ago).order(:created_at).lock("FOR UPDATE SKIP LOCKED").first
      if next_record
        next_record.update!(status: "processing", locked_at: lease, attempts: next_record.attempts + 1)
      end
      next_record
    end
    return false unless record
    begin
      AccountMailer.notification(record).deliver_now
      Workflow.run { Notification.where(id: record.id, locked_at: lease).update_all(status: "sent", sent_at: Time.current, locked_at: nil, last_error: nil) }
    rescue StandardError => error
      Workflow.run do
        Notification.where(id: record.id, locked_at: lease).update_all(status: record.attempts >= 5 ? "failed" : "pending", available_at: (2**record.attempts).minutes.from_now, locked_at: nil, last_error: error.class.name)
      end
      Rails.logger.error("Email notification #{record.id} failed: #{error.class.name}")
    end
    true
  end
end
