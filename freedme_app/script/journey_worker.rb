# Journey maintenance and durable SMS outbox polling. Live delivery requires explicit configuration.
Journeys::Support.guard!
running = true
Signal.trap("TERM") { running = false }
Signal.trap("INT") { running = false }
while running
  begin
    Journeys::Deadlines.run!
    Integrations::SmsDispatcher.run!
    Privacy::ManagedBackup.run_due!
  rescue StandardError => error
    Rails.logger.error("Local journey timer failed: #{error.class.name}; retrying in 30 seconds")
  end
  sleep 30 if running
end
