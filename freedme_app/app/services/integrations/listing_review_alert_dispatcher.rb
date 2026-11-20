module Integrations
  class ListingReviewAlertDispatcher
    def self.run!(mailer: ModeratorMailer)
      pending = ListingReviewAlert.where(sms_state: "queued")
      unless Rails.env.production? && ENV["EMAIL_PROVIDER"] != "ses"
        pending = pending.or(ListingReviewAlert.where(email_state: "queued"))
      end
      pending.limit(100).find_each do |alert|
        claimed_email = false
        alert.with_lock do
          next unless alert.email_state == "queued" || alert.sms_state == "queued"
          account = alert.account
          revision = alert.revision
          listing = Listing.find(revision.listing_id)
          unless account.status == "active" && AccountRole.exists?(account_id: account.id, role: "moderator") &&
              listing.status == "pending_review" && listing.current_revision_id == revision.id
            alert.update!(email_state: "suppressed", sms_state: "suppressed")
            next
          end
          if alert.sms_state == "queued"
            contact = AccountContact.find_by(account_id: account.id, kind: "mobile", revoked_at: nil)
            if contact&.verified_at && SmsConsent.allowed?(contact.lookup_hmac, account_id: contact.account_id)
              SmsGateway.new.deliver(to: Journeys::Support.decrypt(contact.value_ciphertext), template: "moderator_listing_review",
                parameters: {review_link: ListingReviewAlert.review_url(listing.id)}, idempotency_key: "listing-review-#{alert.id}", account_id: account.id)
              alert.update!(sms_state: "enqueued")
            else
              alert.update!(sms_state: "missing_contact_or_consent")
            end
          end
          next unless alert.email_state == "queued"
          contact = StaffCredential.find_by(account_id: account.id)&.email_contact
          unless contact && contact.revoked_at.nil?
            alert.update!(email_state: "missing_contact")
            next
          end
          # Leave unconfigured production email queued for operator setup.
          next if Rails.env.production? && ENV["EMAIL_PROVIDER"] != "ses"
          alert.update!(email_state: "sending")
          claimed_email = true
        end
        next unless claimed_email
        begin
          contact = StaffCredential.find_by!(account_id: alert.account_id).email_contact
          mailer.listing_review(email: Journeys::Support.decrypt(contact.value_ciphertext),
            review_url: ListingReviewAlert.review_url(alert.revision.listing_id)).deliver_now
          alert.update!(email_state: Rails.application.config.action_mailer.delivery_method == :smtp ? "sent" : "simulated")
        rescue StandardError => error
          # An SMTP timeout can occur after acceptance. Do not blindly resend.
          alert.update!(email_state: "failed")
          Rails.logger.error("Moderator email alert #{alert.id} failed: #{error.class.name}")
        end
      end
    end
  end
end
