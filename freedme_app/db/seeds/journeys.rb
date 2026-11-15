# FR003/026 registration fixtures; FR004/006 inventory; FR018 simulated notifications.
# No real verification, policy approval, authentication bypass or SMS transmission.
require "openssl"
module JourneySeeds
  PEOPLE = [
    [1, "Nina Shah", "Fremont", "donor", "+15105550101"],
    [2, "David Chen", "Newark", "donor", "+15105550102"],
    [3, "Maya Patel", "Fremont", "recipient", "+15105550103"],
    [4, "Alex Rivera", "Newark", "recipient", "+15105550104"],
    [5, "Sam Morgan", "Fremont", "moderator", "+15105550105"]
  ].freeze
  ITEMS = [
    ["walkers", "Folding walker"], ["canes", "Adjustable walking cane"],
    ["shower_chairs", "Shower chair"], ["crutches", "Adjustable crutches"],
    ["manual_wheelchairs", "Manual wheelchair"]
  ].freeze
  def self.id(n)
    "019a0000-0000-7000-8000-#{format('%012d', n)}"
  end
  def self.load!
    raise "Journey fixtures are development/test only" unless Journeys::Support.enabled?
    ApplicationRecord.transaction do
      key = Rails.application.key_generator.generate_key("freedme fictional seed contacts v1", 32)
      encryptor = ActiveSupport::MessageEncryptor.new(key)
      PEOPLE.each do |n, name, town, role, phone|
        account = Account.find_or_create_by!(id: id(n)) { |a| a.assign_attributes(display_name: name, public_locality: town, status: "active") }
        AccountRole.find_or_create_by!(account_id: account.id, role: role)
        AccountContact.find_or_create_by!(id: id(100+n)) do |c|
          c.assign_attributes(account_id: account.id, kind: "mobile", value_ciphertext: encryptor.encrypt_and_sign(phone),
            lookup_hmac: OpenSSL::HMAC.digest("SHA256", key, phone), key_version: "fictional-seed-v1", verified_at: Time.current)
        end
        Integrations::SmsGateway.new.deliver(to: phone, template: "registration_welcome",
          parameters: {display_name: name}, idempotency_key: "journey-seed-welcome-#{n}")
      end
      # Explicitly UNAPPROVED fixture references; never enable production pilot gates.
      policy = PolicyVersion.find_or_create_by!(id: id(200)) do |p|
        p.assign_attributes(kind: "fictional_test_fixture", version: "journey-v1", content_sha256: Digest::SHA256.hexdigest("UNAPPROVED TEST FIXTURE"),
          content_object_key: "test-only/not-a-policy", configuration: {test_only: true})
      end
      [1,2].each do |donor|
        town = PEOPLE[donor-1][2]
        area = ServiceArea.find_or_create_by!(id: id(210+donor)) do |a|
          a.assign_attributes(policy_id: policy.id, zip_code: donor == 1 ? "94536" : "94560", county: "Alameda", city: town)
        end
        ITEMS.each_with_index do |(category, title), index|
          config = EquipmentConfiguration.find_or_create_by!(id: id(300+index)) do |c|
            c.assign_attributes(category_id: Category.find_by!(code: category).id, policy_id: policy.id, code: "fictional-#{category}", allowed: false)
          end
          number = donor*1000+index
          next if Listing.exists?(id: id(number)) # Never reset a tester's progress.
          listing = Listing.create!(id: id(number), donor_id: id(donor), status: "draft")
          revision = ListingRevision.create!(id: id(number+100), listing_id: listing.id, revision_no: 1,
            configuration_id: config.id, service_area_id: area.id, offer_kind: index == 4 ? "loan" : "gift",
            loan_until: index == 4 ? Date.current + 60 : nil,
            title: "#{title} — #{PEOPLE[donor-1][1].split.first} (sample)",
            description: "FICTIONAL TEST EQUIPMENT. #{title}; inspect dimensions, fit and capacity before any real use. No actual item is offered.",
            public_locality: town, condition_code: index == 0 ? "new" : "gently_used",
            condition_description: "Simulated disclosure for journey testing only", no_missing_parts_affirmed: true,
            fully_functional_affirmed: true, modifications: "None reported (sample)", cleaning_status: "Cleaned (sample)",
            pickup_availability: "Saturday, 10 AM–noon at a public library (sample)", free_item_affirmed: true,
            truthfulness_affirmed: true, submitted_at: Time.current)
          listing.update!(current_revision_id: revision.id, status: "pending_review")
          Integrations::SmsGateway.new.deliver(to: PEOPLE[donor-1][4], template: "listing_submitted", parameters: { item_title: revision.title },
            idempotency_key: "journey-seed-listing-#{number}")
        end
      end
    end
  end
end
