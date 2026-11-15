require 'test_helper'
require Rails.root.join('db/seeds/journeys')

class PrivacyRetentionTest < ActiveSupport::TestCase
  setup do
    load Rails.root.join('db/seeds.rb')
    JourneySeeds.load!
    @donor = Account.find(JourneySeeds.id(1))
    @recipient = Account.find(JourneySeeds.id(3))
    @moderator = Account.find(JourneySeeds.id(5))
  end

  def arrange(number = 1000, accept: true)
    listing = Listing.find(JourneySeeds.id(number))
    Journeys::Workflow.new(@moderator).review!(listing.id, 'approve', 'Test review')
    exchange = Journeys::Workflow.new(@recipient).request!(listing.id, consent: '1', outcome: 'pass')
    Journeys::Workflow.new(@donor).change!(exchange.id, 'approve', meeting_at: 2.days.from_now.strftime('%Y-%m-%dT12:00'), location: 'Public library')
    @proposal = HandoffProposal.find_by!(exchange_id: exchange.id)
    Journeys::Workflow.new(@recipient).change!(exchange.id, 'accept', proposal_id: @proposal.id) if accept
    exchange.reload
  end

  def document(exchange)
    IdentityDocumentUpload.create!(account_id: @recipient.id, listing_id: exchange.listing_id,
      revision_id: exchange.revision_id, exchange_id: exchange.id, document_kind: 'utility_bill',
      state: 'confirmed', purge_due_at: 7.days.from_now,
      image_ciphertext: IdentityDocuments::Vault.encrypt('PRIVATE IMAGE'),
      fields_ciphertext: IdentityDocuments::Vault.encrypt({first_name: 'Private'}.to_json))
  end

  test 'gift confirmation deletes source image immediately but retains private extracted fields' do
    exchange = arrange
    upload = document(exchange)
    question = EquipmentQuestion.create!(listing_id: exchange.listing_id, donor_id: @donor.id,
      requester_id: @recipient.id, question_ciphertext: Journeys::Support.encrypt('Private conversation'),
      key_version: 'local', idempotency_key: SecureRandom.uuid)
    Journeys::Workflow.new(@donor).change!(exchange.id, 'handoff')
    assert_equal 'gift_confirmed', exchange.reload.retention_end_reason
    assert_nil upload.reload.image_ciphertext
    assert_equal 'Private', upload.extracted_fields['first_name']
    assert question.reload.archived_at
    Privacy::Reporting.run!
    Privacy::Reporting.run!
    assert_equal 1, ReportingArchive.where(exchange_id: exchange.id).count
    report = Privacy::Reporting.summary.to_json
    %w[Private Maya Nina Public address].each { |word| refute_includes report, word }
    refute_includes report, exchange.id
  end

  test 'gift elapsed end requires agreement and never fabricates physical handoff' do
    exchange = arrange
    deadline = @proposal.meeting_at + 7.days
    assert_nil Privacy::ExchangeRetention.end_event(exchange, now: deadline - 1.second)
    Privacy::ExchangeRetention.apply!(exchange, now: deadline)
    assert_equal 'gift_pickup_elapsed', exchange.reload.retention_end_reason
    assert_equal 'reserved', exchange.state
    refute ExchangeEvent.exists?(exchange_id: exchange.id, event_type: 'handoff_confirmed')
  end

  test 'unaccepted proposal does not end gift retention' do
    exchange = arrange(1000, accept: false)
    assert_nil Privacy::ExchangeRetention.end_event(exchange, now: @proposal.meeting_at + 8.days)
  end

  test 'loan handoff and pickup deadline do not end retention but recipient return does' do
    exchange = arrange(1004)
    upload = document(exchange)
    Journeys::Workflow.new(@donor).change!(exchange.id, 'handoff')
    assert_nil Privacy::ExchangeRetention.end_event(exchange.reload, now: @proposal.meeting_at + 8.days)
    assert upload.reload.image_ciphertext
    Journeys::Workflow.new(@recipient).change!(exchange.id, 'return')
    assert_equal 'loan_return_confirmed', exchange.reload.retention_end_reason
    assert_nil upload.reload.image_ciphertext
  end

  test 'source image expires at seven days even with no exchange end' do
    exchange = arrange(1004)
    upload = document(exchange)
    travel_to upload.purge_due_at + 1.second do
      IdentityDocuments::Vault.purge!
      assert_nil upload.reload.image_ciphertext
      assert upload.fields_ciphertext
    end
  end
end
