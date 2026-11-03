require "test_helper"
require Rails.root.join("db/seeds/journeys")

class PickupFollowupsTest < ActiveSupport::TestCase
  setup do
    load Rails.root.join("db/seeds.rb")
    JourneySeeds.load!
    @donor = Account.find(JourneySeeds.id(1))
    @recipient = Account.find(JourneySeeds.id(3))
    listing = Listing.find(JourneySeeds.id(1000))
    Journeys::Workflow.new(Account.find(JourneySeeds.id(5))).review!(listing.id, "approve", "Test review")
    @exchange = Journeys::Workflow.new(@recipient).request!(listing.id, consent: "1", outcome: "pass")
    @donor_flow = Journeys::Workflow.new(@donor)
    @recipient_flow = Journeys::Workflow.new(@recipient)
    @donor_flow.change!(@exchange.id, "approve", meeting_at: 2.days.from_now.iso8601, location: "Public library")
    @proposal = HandoffProposal.where(exchange_id: @exchange.id).order(revision: :desc).first!
    @recipient_flow.change!(@exchange.id, "accept", proposal_id: @proposal.id)
  end

  def messages
    SimulatedSmsMessage.where(template_code: "pickup_followup", idempotency_key: "pickup-followup-#{@proposal.id}")
  end

  test "sends at 24 hours after pickup once with recipient donor item and local time" do
    travel_to(@proposal.meeting_at + 24.hours - 1.second) { Journeys::PickupFollowups.run! }
    assert_equal 0, messages.count
    travel_to(@proposal.meeting_at + 24.hours) do
      2.times { Journeys::PickupFollowups.run! }
    end
    assert_equal 1, messages.count
    message = messages.first!
    assert_equal Journeys::Support.decrypt(AccountContact.find_by!(account_id: @recipient.id, kind: "mobile", revoked_at: nil).value_ciphertext), message.recipient
    assert_includes message.body, @donor.display_name
    assert_includes message.body, ListingRevision.find(@exchange.revision_id).title
    assert_includes message.body, @proposal.meeting_at.in_time_zone.strftime("%-I:%M %p %Z")
    assert_includes message.body, "Please reply YES"
    assert_includes message.body, "/s/requests"
  end

  test "old arrangement does not send after an unaccepted counterproposal" do
    @recipient_flow.change!(@exchange.id, "propose", proposal_id: @proposal.id,
      meeting_at: 5.days.from_now.iso8601, location: "Another library")
    travel_to(@proposal.meeting_at + 24.hours) { Journeys::PickupFollowups.run! }
    assert_equal 0, messages.count
  end

  test "accepted reschedule uses the new pickup time" do
    @recipient_flow.change!(@exchange.id, "propose", proposal_id: @proposal.id,
      meeting_at: 5.days.from_now.iso8601, location: "Another library")
    latest = HandoffProposal.where(exchange_id: @exchange.id).order(revision: :desc).first!
    @donor_flow.change!(@exchange.id, "accept", proposal_id: latest.id)
    travel_to(@proposal.meeting_at + 24.hours) { Journeys::PickupFollowups.run! }
    assert_equal 0, messages.count
    travel_to(latest.meeting_at + 24.hours) { Journeys::PickupFollowups.run! }
    assert SimulatedSmsMessage.exists?(idempotency_key: "pickup-followup-#{latest.id}")
  end

  test "confirmed handoff does not receive a redundant pickup question" do
    @recipient_flow.change!(@exchange.id, "handoff")
    travel_to(@proposal.meeting_at + 24.hours) { Journeys::PickupFollowups.run! }
    assert_equal 0, messages.count
  end

  test "cancelled request does not receive a pickup question" do
    @recipient_flow.change!(@exchange.id, "cancel")
    travel_to(@proposal.meeting_at + 24.hours) { Journeys::PickupFollowups.run! }
    assert_equal 0, messages.count
  end
end
