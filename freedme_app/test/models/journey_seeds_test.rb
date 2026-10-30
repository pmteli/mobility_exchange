require "test_helper"
require Rails.root.join("db/seeds/journeys")

class JourneySeedsTest < ActiveSupport::TestCase
  test "repeatable fictional accounts and inventory leave real controls closed" do
    load Rails.root.join("db/seeds.rb")
    2.times { JourneySeeds.load! }
    assert_equal 5, Account.where(id: (1..5).map { |n| JourneySeeds.id(n) }).count
    assert_equal 5, AccountContact.where(key_version: "fictional-seed-v1").where.not(verified_at: nil).count
    [1, 2].each do |donor|
      listings = Listing.where(donor_id: JourneySeeds.id(donor))
      assert_equal 5, listings.count
      revisions = ListingRevision.where(listing_id: listings.select(:id))
      assert_equal 5, revisions.distinct.count(:configuration_id)
      assert_equal 1, revisions.where(offer_kind: "loan").count
      assert_equal ["pending_review"], listings.distinct.pluck(:status)
    end
    assert_equal 15, SimulatedSmsMessage.where("idempotency_key LIKE ?", "journey-seed-%").count
    refute PilotControl.first!.loans_enabled
    refute PilotControl.first!.evidence_collection_enabled
    assert_nil PolicyVersion.find(JourneySeeds.id(200)).approved_at
    refute AvailableListingCard.where(donor_id: [JourneySeeds.id(1), JourneySeeds.id(2)]).exists?
  end

  test "SMS substitutes parameters and remains explicitly simulated" do
    load Rails.root.join("db/seeds.rb")
    message = Integrations::SmsGateway.new.deliver(to: "+15105550103", template: "request_approved", parameters: {item_title: "Sample walker"})
    assert_instance_of SimulatedSmsMessage, message
    assert_includes message.body, "Sample walker"
    assert_equal "+15105550103", message.recipient
  end
end
