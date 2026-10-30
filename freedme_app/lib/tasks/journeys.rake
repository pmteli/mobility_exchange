namespace :journeys do
  desc "Process local simulated request/offer deadlines and seven-day follow-up tasks"
  task tick: :environment do
    Journeys::Deadlines.run!
    puts "Local journey deadlines processed. No external SMS sent."
  end
end
namespace :journeys do
  desc "Re-key only the five fictional seed phone contacts after installing a stable local secret"
  task refresh_fixture_contacts: :environment do
    Journeys::Support.guard!
    require Rails.root.join("db/seeds/journeys")
    AccountContact.transaction do
      JourneySeeds::PEOPLE.each do |n, _name, _town, _role, phone|
        contact = AccountContact.find_by!(id: JourneySeeds.id(100+n), key_version: "fictional-seed-v1")
        contact.update!(value_ciphertext: Journeys::Support.encrypt(phone), lookup_hmac: Journeys::Support.digest(phone))
      end
    end
    puts "Five fictional contacts re-keyed. No real contact data changed."
  end
end
