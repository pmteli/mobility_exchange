# Idempotent reference data only. Never enables pilot gates or overwrites approved policies.
# Database notification templates below are historical reference data.
# Active simulated SMS wording comes exclusively from config/locales/en.yml.
ApplicationRecord.transaction do
  ApplicationRecord.connection.execute(<<~SQL)
INSERT INTO freedme.pilot_controls(singleton) VALUES (true) ON CONFLICT DO NOTHING;
INSERT INTO freedme.categories(code,name) VALUES ('walkers','Walkers'),('canes','Canes'),('shower_chairs','Shower chairs'),('commodes','Commodes'),('crutches','Crutches'),('manual_wheelchairs','Manual wheelchairs'),('other','Other') ON CONFLICT DO NOTHING;
INSERT INTO freedme.notification_templates(code,version,body) VALUES
('registration_welcome',2,'Welcome to FreeDME {display_name}. Take the next step to either donate, lend or find a mobility equipment for yourself or your loved ones. Visit https://freedme.org'),
('listing_submitted',2,'Thank you for offering {item_title} to a neighbor. Your listing is under review. You will be notified when it is published.'),
('request_received',1,'{verified_name} from {town} has requested your {item_title}. You may approve or decline the request. If the item is no longer available, please indicate “not available”. Please respond within 48 hours.'),
('donor_approval_ack',1,'The requester is notified of your approval as well as the proposed location and time for the hand-off. We will notify you when the requester accepts/rejects your offer'),
('request_approved',1,'Your request for the {item_title} has been approved by the donor. Please review the proposed pick up location and time and respond.'),
('request_declined',1,'Your request for “{item_title}” has been declined by the donor. You may review the inventory for similar items and make a new request.'),
('item_unavailable',1,'Your requested equipment ({item_title}) is no longer available. You may review the inventory for similar items and make a new request.'),
('question_received',1,'An interested recipient has a question about your equipment. Open My Activity to answer.'),
('question_answered',1,'The donor has answered your question. Open My Activity to view the answer.'),
('handoff_proposed',1,'A new pickup time and location have been suggested. Open My Activity to review.'),
('handoff_accepted',1,'Your proposed pickup arrangement has been accepted. Open My Activity for details.') ON CONFLICT DO NOTHING;
  SQL
end

# Explicit opt-in; reference-only seeds remain the default in every environment.
if ENV["SEED_JOURNEYS"] == "1"
  require Rails.root.join("db/seeds/journeys")
  JourneySeeds.load!
end
