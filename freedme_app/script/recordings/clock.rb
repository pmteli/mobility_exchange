abort 'Isolated recording mode only' unless ENV['FREEDME_RECORDING_MODE']=='true' && ApplicationRecord.connection.select_value('SELECT current_database()')=='freedme_recording_demo'
exchange=Exchange.find(ARGV.fetch(0))
case ARGV.fetch(1)
when 'expire'
  abort 'Expected pending recording request' unless exchange.state=='pending'
  require 'active_support/testing/time_helpers'
  include ActiveSupport::Testing::TimeHelpers
  travel_to(exchange.pending_expires_at + 1.minute) { Journeys::Deadlines.run! }
when 'pickup'
  abort 'Expected reserved recording request' unless exchange.state=='reserved'
  proposal=HandoffProposal.where(exchange_id: exchange.id).order(revision: :desc).first!
  abort 'Expected agreed pickup' unless HandoffAcceptance.exists?(proposal_id: proposal.id)
  require 'active_support/testing/time_helpers'
  include ActiveSupport::Testing::TimeHelpers
  travel_to(proposal.meeting_at + 24.hours) { 2.times { Journeys::PickupFollowups.run! } }
  abort 'Expected exactly one follow-up' unless SimulatedSmsMessage.where(idempotency_key: "pickup-followup-#{proposal.id}").count==1
when 'followup'
  abort 'Expected reserved recording request' unless exchange.state=='reserved'
  as_of=ApplicationRecord.connection.quote(exchange.reserved_at + 8.days)
  ApplicationRecord.connection.execute("SELECT freedme.enqueue_handoff_followups(#{as_of}::timestamptz)")
else
  abort 'Unknown recording clock action'
end
puts "Recording-only clock advanced: #{ARGV[1]}"
