module Journeys
  class Deadlines
    def self.run!
      Support.guard!
      Exchange.where("(state='pending' AND pending_expires_at<=?) OR (state='offered' AND offer_expires_at<=?)", Time.current, Time.current).find_each do |exchange|
        Listing.find(exchange.listing_id).with_lock do |listing|
          exchange.lock!
          next unless (exchange.state == "pending" && exchange.pending_expires_at <= Time.current) || (exchange.state == "offered" && exchange.offer_expires_at <= Time.current)
          exchange.update!(state: "expired", closed_at: Time.current, closure_reason: "deadline")
          Listing.find(exchange.listing_id).update!(status: "unavailable")
          ExchangeEvent.create!(exchange_id: exchange.id, event_type: "expired", idempotency_key: SecureRandom.uuid)
          [exchange.donor, exchange.requester].each do |account|
            Support.notify(account, "request_expired", { item_title: ListingRevision.find(exchange.revision_id).title })
          end
        end
      end
      ApplicationRecord.connection.execute("SELECT freedme.enqueue_handoff_followups()")
    end
  end
end
