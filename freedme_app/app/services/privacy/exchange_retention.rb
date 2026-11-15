module Privacy
  # This lifecycle is deliberately separate from physical handoff state.
  class ExchangeRetention
    def self.end_event(exchange, now: Time.current)
      revision = ListingRevision.find(exchange.revision_id)
      type = revision.offer_kind == 'gift' ? 'handoff_confirmed' : 'return_confirmed'
      confirmation = ExchangeEvent.where(exchange_id: exchange.id, event_type: type)
        .where('occurred_at <= ?', now).minimum(:occurred_at)
      if revision.offer_kind == 'loan'
        return [confirmation, 'loan_return_confirmed'] if confirmation
        return nil
      end
      candidates = []
      candidates << [confirmation, 'gift_confirmed'] if confirmation
      # Only the latest proposal counts: an unaccepted counterproposal is not an agreement.
      if %w[reserved completed].include?(exchange.state)
        proposal = HandoffProposal.where(exchange_id: exchange.id).order(revision: :desc).first
        if proposal && HandoffAcceptance.exists?(proposal_id: proposal.id, exchange_id: exchange.id)
          deadline = proposal.meeting_at + 7.days
          candidates << [deadline, 'gift_pickup_elapsed'] if deadline <= now
        end
      end
      candidates.min_by(&:first)
    end

    def self.apply!(exchange, now: Time.current)
      exchange.with_lock do
        unless exchange.retention_ended_at
          ending = end_event(exchange, now: now)
          return unless ending
          exchange.update!(retention_ended_at: ending.first, retention_end_reason: ending.last)
        end
        DisclosureGrant.where(exchange_id: exchange.id, revoked_at: nil).update_all(revoked_at: now)
        IdentityDocumentUpload.where(exchange_id: exchange.id, image_deleted_at: nil)
          .update_all(image_ciphertext: nil, image_deleted_at: now, updated_at: now)
        # A Q&A thread is listing/participant scoped, not exchange scoped. Do not archive
        # it while the same pair has another live exchange for this equipment.
        other_live = Exchange.where(listing_id: exchange.listing_id, donor_id: exchange.donor_id,
          requester_id: exchange.requester_id, retention_ended_at: nil).where.not(id: exchange.id)
          .where(state: %w[pending offered reserved loaned]).exists?
        unless other_live
          EquipmentQuestion.where(listing_id: exchange.listing_id, donor_id: exchange.donor_id,
            requester_id: exchange.requester_id, archived_at: nil).where('asked_at <= ?', exchange.retention_ended_at)
            .update_all(archived_at: now)
        end
      end
    end

    def self.run!(now: Time.current)
      Exchange.where(state: %w[reserved completed]).or(Exchange.where.not(retention_ended_at: nil)).find_each do |exchange|
        apply!(exchange, now: now)
      end
    end
  end
end
