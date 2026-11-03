module Journeys
  # FR018 / FR027: recipient follow-up, 24 elapsed hours after the latest
  # mutually accepted pickup time (explicit user decision, 2 November 2026).
  class PickupFollowups
    def self.run!
      Support.guard!
      Exchange.where(state: "reserved", paused_reason: nil).find_each do |exchange|
        listing = Listing.find(exchange.listing_id)
        listing.with_lock do
          exchange.lock!
          next unless exchange.state == "reserved" && exchange.paused_reason.nil?
          next if ExchangeEvent.where(exchange_id: exchange.id, event_type: "handoff_confirmed").exists?
          next if Restriction.where(released_at: nil).where(
            "listing_id = ? OR account_id IN (?)", listing.id, [exchange.donor_id, exchange.requester_id]
          ).exists?

          proposal = HandoffProposal.where(exchange_id: exchange.id).order(revision: :desc).first
          next unless proposal && proposal.meeting_at <= 24.hours.ago
          next unless HandoffAcceptance.where(proposal_id: proposal.id, exchange_id: exchange.id).exists?

          pickup = proposal.meeting_at.in_time_zone(proposal.display_timezone)
          Support.notify(exchange.requester, "pickup_followup", {
            item_title: ListingRevision.find(exchange.revision_id).title,
            donor_name: exchange.donor.display_name,
            date: pickup.strftime("%b %-d, %Y"), time: pickup.strftime("%-I:%M %p %Z")
          }, key: "pickup-followup-#{proposal.id}")
        end
      end
    end
  end
end
