require 'test_helper'
require Rails.root.join('db/seeds/journeys')

class ListingReviewAlertTest < ActiveSupport::TestCase
  setup do
    load Rails.root.join('db/seeds.rb')
    JourneySeeds.load!
    @staff = Staff::Provisioner.create!(email: 'reviewer@example.test', username: 'review-alert-staff',
      password: 'test-password-only', first_name: 'Review', last_name: 'Staff', role: 'moderator').account
    @listing = Listing.first
    @listing.update!(status: 'pending_review')
    @revision = ListingRevision.find(@listing.current_revision_id)
    @contact = AccountContact.create!(account_id: @staff.id, kind: 'mobile', verified_at: Time.current,
      lookup_hmac: Journeys::Support.digest('+15105550999'), value_ciphertext: Journeys::Support.encrypt('+15105550999'), key_version: 'fictional-seed-v1')
    Integrations::SmsConsent.grant!(@staff, key: SecureRandom.uuid)
    ActionMailer::Base.deliveries.clear
  end
  def queue
    ListingReviewAlert.enqueue!(@revision)
    ListingReviewAlert.find_by!(account_id: @staff.id, revision_id: @revision.id)
  end
  test 'submission alerts are deduplicated and both channels link to the item' do
    row = queue
    queue
    assert_equal 1, ListingReviewAlert.where(account_id: @staff.id, revision_id: @revision.id).count
    2.times { Integrations::ListingReviewAlertDispatcher.run! }
    assert_equal 'simulated', row.reload.email_state
    assert_equal 'enqueued', row.sms_state
    emails = ActionMailer::Base.deliveries.select { |mail| mail.to.include?('reviewer@example.test') }
    assert_equal 1, emails.length
    assert_includes emails.first.body.to_s, "/moderator/listings/#{@listing.id}"
    messages = SimulatedSmsMessage.where(idempotency_key: "listing-review-#{row.id}")
    assert_equal 1, messages.count
    assert_includes messages.first.body, "/moderator/listings/#{@listing.id}"
  end
  test 'SMS opt out does not block email' do
    ConsentEvent.create!(account_id: @staff.id, contact_id: @contact.id, purpose: 'routine_sms', action: 'stop', idempotency_key: SecureRandom.uuid)
    row = queue
    Integrations::ListingReviewAlertDispatcher.run!
    assert_equal 'missing_contact_or_consent', row.reload.sms_state
    assert_equal 'simulated', row.email_state
  end
  test 'closed accounts and reviewed items are suppressed' do
    row = queue
    @listing.update!(status: 'rejected')
    Integrations::ListingReviewAlertDispatcher.run!
    assert_equal 'suppressed', row.reload.email_state
    assert_equal 'suppressed', row.sms_state
  end
  test 'rolled back submissions do not leave alerts' do
    assert_no_difference 'ListingReviewAlert.count' do
      ApplicationRecord.transaction { queue; raise ActiveRecord::Rollback }
    end
  end
  test 'email failure is recorded without duplicate SMS or automatic resend' do
    row = queue
    failure = Object.new
    def failure.deliver_now; raise IOError, 'test transport failure'; end
    mailer = Object.new
    mailer.define_singleton_method(:listing_review) { |**args| failure }
    Integrations::ListingReviewAlertDispatcher.run!(mailer: mailer)
    assert_equal 'failed', row.reload.email_state
    assert_equal 'enqueued', row.sms_state
    Integrations::ListingReviewAlertDispatcher.run!
    assert_equal 1, SimulatedSmsMessage.where(idempotency_key: "listing-review-#{row.id}").count
    assert_equal 'failed', row.reload.email_state
  end
  test 'missing staff email and mobile are recorded without raising' do
    @contact.update!(revoked_at: Time.current)
    StaffCredential.find(@staff.id).email_contact.update!(revoked_at: Time.current)
    row = queue
    Integrations::ListingReviewAlertDispatcher.run!
    assert_equal 'missing_contact', row.reload.email_state
    assert_equal 'missing_contact_or_consent', row.sms_state
  end

end
