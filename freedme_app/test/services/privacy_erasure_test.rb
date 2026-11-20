require 'test_helper'
require 'tmpdir'
require Rails.root.join('db/seeds/journeys')
class PrivacyErasureTest < ActiveSupport::TestCase
  setup do
    load Rails.root.join('db/seeds.rb')
    JourneySeeds.load!
    @account = Account.find(JourneySeeds.id(3))
    @admin = Account.find(JourneySeeds.id(5))
    AccountRole.create!(account_id: @admin.id, role: 'administrator')
    PrivacyDeletionRequest.create!(account_id: @account.id)
    @previous = ENV.to_h.slice('PRIVACY_BACKUP_DIRECTORY', 'PRIVACY_ERASURE_MAINTENANCE')
    @directory = Dir.mktmpdir('privacy-erasure-test-')
    ENV['PRIVACY_BACKUP_DIRECTORY'] = @directory
    ENV['PRIVACY_ERASURE_MAINTENANCE'] = '1'
    @service = Privacy::Erasure.new(@account, @admin)
  end
  teardown do
    %w[PRIVACY_BACKUP_DIRECTORY PRIVACY_ERASURE_MAINTENANCE].each { |key| ENV.delete(key) }
    @previous.each { |key, value| ENV[key] = value }
    FileUtils.rm_f(@photo_path) if @photo_path
    FileUtils.remove_entry(@directory)
  end
  def approve(plan)
    %w[shared_content_reviewed media_reviewed application_logs_reviewed].each { |key| plan[key] = true }
    plan
  end
  test 'refuses unreviewed and stale deletion plans' do
    assert_raises(Privacy::Erasure::Error) { @service.execute!(@service.plan) }
    plan = approve(@service.plan)
    SimulatedSmsMessage.create!(recipient: '+15105550101', template_code: 'test', body: 'New shared content', idempotency_key: SecureRandom.uuid)
    assert_raises(Privacy::Erasure::Error) { @service.execute!(plan) }
    assert_equal 'active', @account.reload.status
    assert AccountContact.exists?(account_id: @account.id)
  end
  test 'erases requester identity and contacts while preserving donor and shared transaction' do
    donor = Account.find(JourneySeeds.id(1))
    listing = Listing.find(JourneySeeds.id(1000))
    Journeys::Workflow.new(@admin).review!(listing.id, 'approve', 'Test')
    exchange = Journeys::Workflow.new(@account).request!(listing.id, consent: '1', outcome: 'pass')
    upload = IdentityDocumentUpload.create!(account_id: @account.id, listing_id: listing.id,
      revision_id: exchange.revision_id, exchange_id: exchange.id, document_kind: 'utility_bill', state: 'confirmed',
      image_ciphertext: 'private source', fields_ciphertext: IdentityDocuments::Vault.encrypt({first_name: 'Maya'}.to_json), purge_due_at: 7.days.from_now)
    Journeys::Support.audit(@account, 'view', upload)
    before_donor = donor.attributes
    backup = File.join(@directory, 'old.backup')
    File.write(backup, 'old encrypted backup')
    plan = approve(@service.plan)
    # This represents administrator review, not an automatic anonymization rule.
    plan['fields'].each { |field| field['value'] = field['value'].to_s.gsub('Maya Patel', '[Deleted requester]').gsub('Maya', '[Deleted requester]') }
    assert @service.execute!(plan)
    assert_equal before_donor, donor.reload.attributes
    assert_equal 'closed_unavailable', exchange.reload.state
    assert_equal 'closed', @account.reload.status
    assert_equal 'Deleted account', @account.display_name
    refute AccountContact.exists?(account_id: @account.id)
    refute IdentityDocumentUpload.exists?(id: upload.id)
    refute AuditEvent.exists?(actor_id: @account.id)
    refute PrivacyDeletionRequest.exists?(account_id: @account.id)
    refute File.exist?(backup)
    assert AccountContact.exists?(account_id: donor.id)
    # Normal append-only protection is restored after maintenance.
    event = AuditEvent.where(actor_id: @admin.id).first!
    assert_raises(ActiveRecord::StatementInvalid) { event.update_columns(reason_code: 'tampered') }
  end
  test 'donor erasure removes owned image files but preserves recipient contact data' do
    donor = Account.find(JourneySeeds.id(1))
    PrivacyDeletionRequest.create!(account_id: donor.id)
    service = Privacy::Erasure.new(donor, @admin)
    listing = Listing.find(JourneySeeds.id(1000))
    key = "#{SecureRandom.uuid}.jpg"
    @photo_path = EquipmentMedia::Photos.path(key)
    FileUtils.mkdir_p(@photo_path.dirname)
    File.write(@photo_path, 'test image')
    photo = ListingPhoto.create!(revision_id: listing.current_revision_id, slot: 5,
      sanitized_object_key: key, mime_type: 'image/jpeg', byte_size: 10)
    plan = approve(service.plan)
    plan['fields'].each { |field| field['value'] = field['value'].to_s.gsub('Nina Shah', '[Deleted donor]').gsub('Nina', '[Deleted donor]') }
    service.execute!(plan)
    refute File.exist?(@photo_path)
    refute ListingPhoto.exists?(id: photo.id)
    assert_equal 'withdrawn', listing.reload.status
    assert_equal 'active', @account.reload.status
    assert AccountContact.exists?(account_id: @account.id)
  end

  test 'SQL failure restores immutable protections and leaves the request pending' do
    plan = approve(@service.plan)
    plan['fields'].find { |field| field['model'] == 'ListingRevision' && field['field'] == 'title' }['value'] = nil
    assert_raises(ActiveRecord::NotNullViolation) { @service.execute!(plan) }
    assert_equal 'active', @account.reload.status
    assert PrivacyDeletionRequest.exists?(account_id: @account.id)
    disabled = ApplicationRecord.connection.select_value("SELECT count(*) FROM pg_trigger WHERE tgname IN ('audit_append_only','consent_append_only','freeze_submitted_revision','agreement_immutable','handoff_proposal_immutable') AND tgenabled='D'")
    assert_equal 0, disabled.to_i
  end

  test 'deleting a member preserves staff messages and contact on the same phone' do
    contact = AccountContact.find_by!(account_id: @account.id, kind: 'mobile', revoked_at: nil)
    staff = Staff::Provisioner.create!(email: 'shared-staff@example.test', username: 'shared-staff', password: 'Test password 123!', first_name: 'Staff', last_name: 'Member', role: 'moderator').account
    shared = AccountContact.create!(account_id: staff.id, kind: 'mobile', lookup_hmac: contact.lookup_hmac, value_ciphertext: contact.value_ciphertext, key_version: contact.key_version, verified_at: Time.current)
    message = SimulatedSmsMessage.create!(recipient_account_id: staff.id, recipient: Journeys::Support.decrypt(contact.value_ciphertext), template_code: 'test', body: 'Staff notice')
    ConsentEvent.create!(account_id: @account.id, contact_id: contact.id, purpose: 'routine_sms', action: 'stop', idempotency_key: SecureRandom.uuid)
    assert @service.execute!(approve(@service.plan))
    assert AccountContact.exists?(shared.id)
    assert SimulatedSmsMessage.exists?(message.id)
    assert Integrations::SmsConsent.carrier_stopped?(shared)
  end

end
