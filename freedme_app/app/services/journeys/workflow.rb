module Journeys
  class Workflow
    ACTIVE = %w[pending offered reserved loaned].freeze
    def initialize(actor)
      Support.guard!
      @actor = actor
      Support.active!(actor)
    end
    def role?(role)
      AccountRole.exists?(account_id: @actor.id, role: role)
    end
    def staff!
      raise Error, "Moderator access required." unless role?("moderator")
    end
    def member!
      raise Error, "A donor or recipient account is required." unless role?("donor") || role?("recipient")
    end
    def title(exchange)
      ListingRevision.find(exchange.revision_id).title
    end
    def event(exchange, type)
      ExchangeEvent.create!(exchange_id: exchange.id, actor_id: @actor.id, event_type: type, idempotency_key: SecureRandom.uuid)
    end
    def listing!(id)
      listing = Listing.find(id)
      raise Error, "Only the donor can change this equipment." unless listing.donor_id == @actor.id
      listing
    end
    def save_listing!(attributes, id: nil)
      member!
      prepared_photos = []
      data = attributes.symbolize_keys
      %i[title description public_locality].each { |key| raise Error, "#{key.to_s.humanize} is required." if data[key].to_s.strip.empty? }
      raise Error, "Title must be at most 120 characters." if data[:title].length > 120
      raise Error, "Description must be at most 4000 characters." if data[:description].length > 4000
      %i[no_missing_parts_affirmed fully_functional_affirmed truthfulness_affirmed].each do |key|
        raise Error, "Confirm all required disclosures." unless data[key] == "1"
      end
      raise Error, "Choose a condition." unless %w[new gently_used good requires_repairs].include?(data[:condition_code])
      raise Error, "Choose gift or loan." unless %w[gift loan].include?(data[:offer_kind])
      loan_until = data[:offer_kind] == "loan" ? Date.iso8601(data[:loan_until].to_s) : nil
      raise Error, "Loan Until must be a future date." if loan_until && loan_until <= Date.current
      original = id ? listing!(id) : nil
      source_revision_id = original&.current_revision_id
      existing = ListingPhoto.where(revision_id: source_revision_id).where.not(sanitized_object_key: "simulation/equipment-placeholder.png").order(:slot).to_a
      removed = Array(data[:remove_photo_ids]).reject(&:blank?)
      raise Error, "Invalid photo selection." unless (removed - existing.map { |p| p.id.to_s }).empty?
      retained = existing.reject { |p| removed.include?(p.id.to_s) }
      uploads = Array(data[:photos]).reject(&:blank?)
      raise Error, "Include between 1 and 5 equipment photos." unless (retained.length + uploads.length).between?(1, 5)
      uploads.each { |upload| prepared_photos << EquipmentMedia::Photos.prepare(upload) }
      photo_data = retained.map { |photo| EquipmentMedia::Photos.copy(photo) } + prepared_photos
      photo_data.each { |photo| EquipmentMedia::Moderation.enforce!(photo, @actor) }
      listing = nil
      ApplicationRecord.transaction do
        policy = LocalPolicy.policy!
        config = EquipmentConfiguration.find_by!(policy_id: policy.id, category_id: data[:category_id])
        listing = id ? listing!(id) : Listing.create!(donor_id: @actor.id)
        listing.lock!
        raise Error, "Equipment was edited elsewhere. Reload before submitting." if listing.current_revision_id != source_revision_id
        Support.active!(@actor, listing)
        raise Error, "Close the active transaction before editing." if Exchange.where(listing_id: listing.id, state: ACTIVE).exists?
        raise Error, "This equipment can no longer be edited." if %w[donated loaned reserved].include?(listing.status)
        area = LocalPolicy.area!(policy, data[:public_locality])
        revision = ListingRevision.create!(listing_id: listing.id, revision_no: listing.revisions.maximum(:revision_no).to_i+1,
          configuration_id: config.id, service_area_id: area.id, offer_kind: data[:offer_kind], loan_until: loan_until,
          title: data[:title], description: data[:description], public_locality: data[:public_locality], condition_code: data[:condition_code],
          condition_description: data[:condition_code].humanize, no_missing_parts_affirmed: true, fully_functional_affirmed: true,
          modifications: "See description", cleaning_status: "Self-reported (simulation)", pickup_availability: ListingRevision.find_by(id: source_revision_id)&.pickup_availability || "To be arranged after approval.",
          free_item_affirmed: true, truthfulness_affirmed: true, submitted_at: Time.current)
        photo_data.each_with_index { |photo, index| ListingPhoto.create!(**photo, revision_id: revision.id, slot: index + 1) }
        listing.update!(current_revision_id: revision.id, status: "pending_review")
        Support.audit(@actor, "listing_submitted", listing)
        Support.notify(@actor, "listing_submitted", { item_title: revision.title })
      end
      listing
    rescue Date::Error
      raise Error, "Enter a valid Loan Until date."
    rescue StandardError
      Array(prepared_photos).each { |photo| FileUtils.rm_f(EquipmentMedia::Photos.path(photo[:sanitized_object_key])) }
      raise
    end
    def review!(id, decision, reason)
      staff!
      raise Error, "Select approve or reject." unless %w[approve reject].include?(decision)
      raise Error, "Provide a review note." if reason.to_s.strip.empty?
      listing = Listing.find(id)
      reviewed_revision = listing.current_revision_id
      if decision == "approve"
        ListingPhoto.where(revision_id: reviewed_revision).each do |photo|
          next if photo.sanitized_object_key == "simulation/equipment-placeholder.png"
          EquipmentMedia::Moderation.enforce!(EquipmentMedia::Photos.copy(photo), listing.donor)
        end
      end
      listing.with_lock do
        raise Error, "Listing changed during review. Reload and review again." if listing.current_revision_id != reviewed_revision
        raise Error, "This listing is no longer awaiting review." unless listing.status == "pending_review"
        Support.active!(listing.donor, listing)
        old = ListingRevision.find(listing.current_revision_id)
        if decision == "approve"
          policy = LocalPolicy.policy!
          category_id = EquipmentConfiguration.find(old.configuration_id).category_id
          # A new immutable revision records simulated screening; never rewrite submitted content.
          revision = ListingRevision.create!(old.attributes.except("id", "created_at", "revision_no", "configuration_id", "service_area_id").merge(
            revision_no: old.revision_no+1, configuration_id: EquipmentConfiguration.find_by!(policy_id: policy.id, category_id: category_id).id,
            service_area_id: LocalPolicy.area!(policy, old.public_locality).id, public_content_checked_at: Time.current))
          photos = ListingPhoto.where(revision_id: old.id).order(:slot).to_a
          if photos.empty? # Historical fictional seeds only; real submissions require photos.
            ListingPhoto.create!(revision_id: revision.id, slot: 1, sanitized_object_key: "simulation/equipment-placeholder.png", mime_type: "image/png",
              byte_size: Rails.root.join("public/simulation/equipment-placeholder.png").size, metadata_stripped_at: Time.current, content_reviewed_at: Time.current, state: "approved")
          else
            photos.each do |photo|
              ListingPhoto.create!(**EquipmentMedia::Photos.copy(photo), revision_id: revision.id, slot: photo.slot, state: "approved", content_reviewed_at: Time.current)
            end
          end
          RecallReview.create!(revision_id: revision.id, reviewer_id: @actor.id, source_url: "https://example.invalid/simulation-only",
            product_identification: "SIMULATION ONLY — no actual recall search", result: "no_match", policy_id: policy.id)
          ListingReview.create!(revision_id: revision.id, reviewer_id: @actor.id, decision: "approved", disclosures_checked: true,
            recall_checked: true, reason: "SIMULATED screening: #{reason}")
          listing.update!(current_revision_id: revision.id, approved_revision_id: revision.id, status: "available",
            last_possession_confirmed_at: Time.current, availability_valid_until: 30.days.from_now)
        else
          ListingReview.create!(revision_id: old.id, reviewer_id: @actor.id, decision: "rejected", disclosures_checked: false, recall_checked: false, reason: reason)
          listing.update!(status: "rejected")
        end
        Support.audit(@actor, "listing_#{decision}", listing)
        Support.notify(listing.donor, decision == "approve" ? "listing_published" : "listing_rejected", { item_title: old.title })
      end
      listing
    end
    def request!(listing_id, consent:, outcome:, retry_id: nil, document_upload: nil)
      member!
      raise Error, "Consent to share your name and ZIP code is required." unless consent == "1"
      if IdentityDocuments::Intake.enabled? && !document_upload
        raise Error, "Upload and confirm your identity document before submitting."
      end
      if document_upload && (document_upload.account_id != @actor.id || document_upload.listing_id != listing_id || document_upload.state != 'extracted' || document_upload.purge_due_at <= Time.current)
        raise Error, "Invalid document confirmation."
      end
      listing = Listing.find(listing_id)
      result = nil
      listing.with_lock do
        Support.active!(@actor, listing)
        raise Error, "You cannot request your own equipment." if listing.donor_id == @actor.id
        raise Error, "This item is no longer available." unless listing.status == "available" && !Exchange.where(listing_id: listing.id, state: ACTIVE).exists?
        revision = ListingRevision.find(listing.approved_revision_id)
        intent = RequestIntent.create!(listing_id: listing.id, requester_id: @actor.id, expires_at: 1.day.from_now, idempotency_key: SecureRandom.uuid)
        if outcome == "fail"
          intent.update!(state: "failed")
          return intent
        end
        raise Error, "Select a verification outcome." unless outcome == "pass"
        policy = LocalPolicy.enable_transaction_fixtures!
        evidence = IdentityEvidence.create!(submitted_by: @actor.id, document_kind: document_upload&.document_kind || "government_id", verification_provider: document_upload ? "textract_requester_confirmed" : "local_simulation_no_document",
          reviewer_id: document_upload ? @actor.id : nil,
          review_state: "approved", reviewed_at: Time.current, valid_until: 30.days.from_now, policy_id: policy.id)
        names = @actor.display_name.split(" ", 2)
        fields = document_upload ? document_upload.extracted_fields.slice(*IdentityDocuments::Extractor::FIELDS) : {first_name: names.first, last_name: names.last || "Sample", home_address: "FICTIONAL ADDRESS — NO DOCUMENT", zip_code: @actor.public_locality[/\d{5}/] || "94536"}
        fields.each do |name, value|
          BorrowerField.create!(evidence_id: evidence.id, field_name: name, value_ciphertext: Support.encrypt(value), key_version: "fictional-seed-v1",
            source: "document", verification: "reviewed_against_evidence", verified_at: Time.current)
        end
        now = Time.current
        result = Exchange.create!(listing_id: listing.id, donor_id: listing.donor_id, requester_id: @actor.id, revision_id: revision.id,
          requested_at: now, pending_reminder_at: now+24.hours, pending_expires_at: now+48.hours, idempotency_key: SecureRandom.uuid,
          proposed_start_date: revision.offer_kind == "loan" ? Date.current : nil, proposed_end_date: revision.loan_until)
        DisclosureGrant.create!(exchange_id: result.id, evidence_id: evidence.id, consented_by: @actor.id, donor_id: listing.donor_id,
          consent_policy_id: policy.id, allowed_fields: %w[first_name last_name zip_code], expires_at: evidence.valid_until)
        intent.update!(state: "submitted", evidence_id: evidence.id, exchange_id: result.id)
        event(result, "requested")
        Support.notify(listing.donor, "request_received", {verified_name: document_upload ? [fields['first_name'],fields['last_name']].join(' ') : @actor.display_name, town: document_upload ? fields['zip_code'] : @actor.public_locality, item_title: revision.title})
        if retry_id.present?
          old = Exchange.find_by!(id: retry_id, requester_id: @actor.id, listing_id: listing.id, state: "expired")
          ExchangeDisplayPreference.find_or_create_by!(exchange_id: old.id, account_id: @actor.id).update!(hidden_at: Time.current, replaced_by_exchange_id: result.id)
        end
      end
      result
    end
    def exchange!(id)
      exchange = Exchange.find(id)
      raise Error, "You are not a participant in this request." unless [exchange.donor_id, exchange.requester_id].include?(@actor.id)
      exchange
    end
    def proposal!(exchange, date, location)
      raise Error, "Enter a public pickup location (maximum 300 characters)." unless location.to_s.strip.length.between?(1, 300)
      meeting = ActiveSupport::TimeZone["America/Los_Angeles"].parse(date.to_s) rescue nil
      raise Error, "Choose a future date and time (Pacific Time)." unless meeting && meeting > Time.current
      revision = ListingRevision.find(exchange.revision_id)
      if revision.offer_kind == "loan" && meeting.in_time_zone("America/Los_Angeles").to_date > revision.loan_until
        raise Error, "Pickup must be on or before Loan Until."
      end
      HandoffProposal.create!(exchange_id: exchange.id, revision: HandoffProposal.where(exchange_id: exchange.id).maximum(:revision).to_i+1,
        proposed_by: @actor.id, meeting_at: meeting, public_location_ciphertext: Support.encrypt(location), key_version: "fictional-seed-v1", idempotency_key: SecureRandom.uuid)
    end
    def change!(id, action, data = {})
      exchange = exchange!(id)
      listing = Listing.find(exchange.listing_id)
      listing.with_lock do
        exchange.lock!
        donor = exchange.donor_id == @actor.id
        recipient = exchange.requester_id == @actor.id
        Support.active!(@actor, listing)
        raise Error, "This transaction is paused." if exchange.paused_reason
        case action
        when "approve"
          raise Error, "Only the donor can approve a pending request." unless donor && exchange.state == "pending"
          now = Time.current
          exchange.update!(state: "offered", offered_at: now, offer_expires_at: now+24.hours)
          proposal!(exchange, data[:meeting_at], data[:location])
          event(exchange, "offered")
          Support.notify(exchange.requester, "request_approved", {item_title: title(exchange)})
          Support.notify(@actor, "donor_approval_ack")
        when "decline", "unavailable"
          raise Error, "Only the donor can decide a pending request." unless donor && exchange.state == "pending"
          exchange.update!(state: action == "decline" ? "declined" : "closed_unavailable", closed_at: Time.current, closure_reason: action)
          listing.update!(status: "unavailable")
          event(exchange, action == "decline" ? "declined" : "unavailable")
          Support.notify(exchange.requester, action == "decline" ? "request_declined" : "item_unavailable", {item_title: title(exchange)})
        when "accept", "propose"
          raise Error, "This offer is no longer active." unless %w[offered reserved].include?(exchange.state)
          if exchange.state == "offered"
            raise Error, "Only the recipient can accept or counter the offer." unless recipient
            exchange.update!(state: "reserved", reserved_at: Time.current)
            listing.update!(status: "reserved")
            event(exchange, "reserved")
          end
          latest = HandoffProposal.where(exchange_id: exchange.id).order(revision: :desc).first!
          raise Error, "The proposal has changed. Reload and review it." unless latest.id == data[:proposal_id]
          if action == "accept"
            HandoffAcceptance.create!(proposal_id: latest.id, exchange_id: exchange.id, accepted_by: @actor.id)
            Support.notify(donor ? exchange.requester : exchange.donor, "handoff_accepted")
          else
            proposal!(exchange, data[:meeting_at], data[:location])
            Support.notify(donor ? exchange.requester : exchange.donor, "handoff_proposed")
          end
        when "handoff"
          raise Error, "Handoff can only be confirmed once from Reserved." unless exchange.state == "reserved"
          loan = ListingRevision.find(exchange.revision_id).offer_kind == "loan"
          exchange.update!(state: loan ? "loaned" : "completed", closed_at: loan ? nil : Time.current)
          listing.update!(status: loan ? "loaned" : "donated")
          event(exchange, "handoff_confirmed")
          ModeratorTask.where(exchange_id: exchange.id, state: %w[open in_progress]).update_all(state: "cancelled", resolved_at: Time.current)
          Support.notify(donor ? exchange.requester : exchange.donor, "handoff_confirmed", { item_title: title(exchange) })
        when "return"
          raise Error, "Only the donor can confirm return of a loaned item." unless donor && exchange.state == "loaned"
          exchange.update!(state: "completed", closed_at: Time.current)
          listing.update!(status: "unavailable")
          event(exchange, "return_confirmed")
          Support.notify(exchange.requester, "return_confirmed", { item_title: title(exchange) })
        when "cancel", "revoke"
          raise Error, "Cancellation/consent revocation is unavailable after handoff." unless %w[pending offered reserved].include?(exchange.state)
          raise Error, "Only the recipient can revoke consent." if action == "revoke" && !recipient
          exchange.update!(state: "cancelled", closed_at: Time.current, closure_reason: action)
          DisclosureGrant.where(exchange_id: exchange.id, revoked_at: nil).update_all(revoked_at: Time.current) if action == "revoke"
          listing.update!(status: "unavailable")
          event(exchange, "cancelled")
          ModeratorTask.where(exchange_id: exchange.id, state: %w[open in_progress]).update_all(state: "cancelled", resolved_at: Time.current)
          Support.notify(donor ? exchange.requester : exchange.donor, "request_cancelled", { item_title: title(exchange) })
        when "hide"
          raise Error, "Only recipients can remove expired requests from their view." unless recipient && exchange.state == "expired"
          ExchangeDisplayPreference.find_or_create_by!(exchange_id: exchange.id, account_id: @actor.id).update!(hidden_at: Time.current)
        else
          raise Error, "Unknown action."
        end
        Support.audit(@actor, "exchange_#{action}", exchange)
      end
      exchange
    end
    def reopen!(id, confirmed)
      listing = listing!(id)
      raise Error, "Confirm that you still have the equipment and it is available." unless confirmed == "1"
      listing.with_lock do
        Support.active!(@actor, listing)
        raise Error, "Only unavailable equipment can be reopened." unless listing.status == "unavailable"
        listing.update!(status: "available", last_possession_confirmed_at: [Time.current, listing.updated_at + Rational(1, 1000)].max, availability_valid_until: 30.days.from_now,
          allocation_generation: listing.allocation_generation+1)
        Support.audit(@actor, "listing_reopened", listing)
      end
    end
    def ask!(id, text)
      member!
      raise Error, "Enter a question of 1–2000 characters." unless text.to_s.strip.length.between?(1,2000)
      listing = Listing.find(id)
      Support.active!(@actor, listing)
      raise Error, "Questions are only available for published equipment offered by someone else." unless listing.status == "available" && listing.donor_id != @actor.id
      ApplicationRecord.transaction do
        question = EquipmentQuestion.create!(listing_id: listing.id, donor_id: listing.donor_id, requester_id: @actor.id,
          question_ciphertext: Support.encrypt(text), key_version: "fictional-seed-v1", idempotency_key: SecureRandom.uuid)
        Support.notify(listing.donor, "question_received")
        question
      end
    end
    def answer!(id, text)
      question = EquipmentQuestion.find_by!(id: id, donor_id: @actor.id)
      raise Error, "Enter an answer of 1–2000 characters." unless text.to_s.strip.length.between?(1,2000)
      question.with_lock do
        Support.active!(@actor, Listing.find(question.listing_id))
        raise Error, "This question has already been answered." unless question.state == "pending"
        question.update!(answer_ciphertext: Support.encrypt(text), state: "answered", answered_at: Time.current, answered_by: @actor.id)
        Support.notify(Account.find(question.requester_id), "question_answered")
      end
    end
  end
end
