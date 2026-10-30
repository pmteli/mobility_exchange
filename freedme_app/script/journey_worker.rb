# Local development timer only; no external messaging provider is invoked.
Journeys::Support.guard!
running = true
Signal.trap("TERM") { running = false }
Signal.trap("INT") { running = false }
while running
  begin
    Journeys::Deadlines.run!
  rescue StandardError => error
    Rails.logger.error("Local journey timer failed: #{error.class.name}; retrying in 30 seconds")
  end
  sleep 30 if running
end
