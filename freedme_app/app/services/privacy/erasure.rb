module Privacy
  # Owner-run maintenance, deliberately not callable from an HTTP action. Shared
  # records survive; an unlinkable-to-contact closed account anchor preserves FKs.
  # A human reviews shared text/media before execution; OCR/regex is not a proof
  # of anonymization. Never send this review material to application logs.
  class Erasure
    class Error < StandardError; end
    CONTENT = {
      'ListingRevision' => %w[title description public_locality condition_description manufacturer model capacity_description missing_parts known_defects modifications cleaning_status pickup_availability],
      'HandoffProposal' => %w[public_location_ciphertext],
      'EquipmentQuestion' => %w[question_ciphertext answer_ciphertext],
      'PrivateMessage' => %w[body_ciphertext],
      'Case' => %w[details_ciphertext next_action closure_reason],
      'CaseAction' => %w[notes_ciphertext],
      'ModeratorTask' => %w[notes_ciphertext outcome],
      'ListingReview' => %w[reason],
      'RecallReview' => %w[product_identification notes_ciphertext source_url],
      'LoanTermsHistory' => %w[reason],
      'TransportBarrier' => %w[reason],
      'Representation' => %w[subject_reference_ciphertext relationship],
      'Agreement' => %w[terms_snapshot_ciphertext],
      'SimulatedSmsMessage' => %w[body],
      'SmsDelivery' => %w[body_ciphertext],
      'Restriction' => %w[reason],
      'OrganizationParticipation' => %w[organization_name contact_ciphertext],
      'TeamProfile' => %w[display_name biography]
    }.freeze
    TRIGGERS = {
      'audit_events' => 'audit_append_only', 'consent_events' => 'consent_append_only',
      'listing_revisions' => 'freeze_submitted_revision', 'agreements' => 'agreement_immutable',
      'handoff_proposals' => 'handoff_proposal_immutable'
    }.freeze

    def initialize(account, reviewer)
      @account, @reviewer = account, reviewer
      raise Error, 'An active administrator must perform privacy maintenance.' unless reviewer.status == 'active' &&
        AccountRole.exists?(account_id: reviewer.id, role: 'administrator') && reviewer.id != account.id
      raise Error, 'A user deletion request is required.' unless PrivacyDeletionRequest.exists?(account_id: account.id)
    end

    def plan
      fields = CONTENT.flat_map do |model_name, columns|
        model = model_name.constantize
        model.order(:id).flat_map do |record|
          columns.filter_map do |column|
            raw = record[column]
            next if raw.nil?
            value = column.end_with?('_ciphertext') ? Journeys::Support.decrypt(raw) : raw
            { 'model' => model_name, 'id' => record.id, 'field' => column,
              'digest' => Digest::SHA256.hexdigest(raw.to_s), 'value' => value }
          end
        end
      end
      media = ListingPhoto.order(:id).pluck(:id, :original_object_key, :sanitized_object_key)
      { 'account_id' => @account.id, 'fields' => fields, 'media' => media,
        'fingerprint' => Digest::SHA256.hexdigest([fields.map { |v| v.except('value') }, media].to_json),
        'shared_content_reviewed' => false, 'media_reviewed' => false,
        'application_logs_reviewed' => false }
    rescue ActiveSupport::MessageEncryptor::InvalidMessage
      raise Error, 'A stored field could not be decrypted. Resolve its key before deletion; no data was changed.'
    end

    def execute!(review)
      # Do not recreate erased phone numbers in SQL debug logs during maintenance.
      logger = ApplicationRecord.logger
      if logger.respond_to?(:silence)
        logger.silence(Logger::FATAL) { perform!(review) }
      elsif logger.nil?
        perform!(review)
      else
        raise Error, 'Privacy maintenance requires a logger supporting thread-local silence.'
      end
    end

    private
    def perform!(review)
      raise Error, 'Enable owner-run privacy maintenance explicitly.' unless ENV['PRIVACY_ERASURE_MAINTENANCE'] == '1'
      unless %w[shared_content_reviewed media_reviewed application_logs_reviewed].all? { |key| review[key] == true }
        raise Error, 'Review shared content, media and application logs first.'
      end
      root = ManagedBackup.directory
      File.open(root.join('.lock'), File::RDWR | File::CREAT, 0600) do |lock|
        lock.flock(File::LOCK_EX)
        ApplicationRecord.transaction(requires_new: true) do
          connection = ApplicationRecord.connection
          # Lock all application tables in a stable order. No new personal content
          # can race the reviewed snapshot. Foreign keys are NEVER disabled.
          tables = connection.select_values("SELECT tablename FROM pg_tables WHERE schemaname='freedme' ORDER BY tablename")
          tables.each { |table| connection.execute("LOCK TABLE freedme.#{connection.quote_column_name(table)} IN SHARE ROW EXCLUSIVE MODE") }
          current = plan
          unless review['account_id'] == @account.id && review['fingerprint'] == current['fingerprint'] &&
              review['fields'].map { |field| field.except('value') } == current['fields'].map { |field| field.except('value') } &&
              review['media'] == current['media']
            raise Error, 'Data changed since review. Generate and review a fresh plan.'
          end
          validate_storage!
          # Every older backup may contain this user. Invalidate all managed
          # copies rather than attempting uncertain in-place redaction.
          root.children.select { |file| file.basename.to_s.match?(/\.(backup|partial|review\.json)\z/) }.each(&:unlink)
          TRIGGERS.each { |table, trigger| connection.execute("ALTER TABLE freedme.#{table} DISABLE TRIGGER #{trigger}") }
          apply_review!(review, current)
          erase_private_records!
          TRIGGERS.each { |table, trigger| connection.execute("ALTER TABLE freedme.#{table} ENABLE TRIGGER #{trigger}") }
          # ALTER TABLE is transactional: exceptions restore all trigger states.
        end
      end
      true
    end

    private
    def validate_storage!
      evidence = IdentityEvidence.where(submitted_by: @account.id)
      if evidence.where.not(restricted_object_key: nil).where.not("restricted_object_key LIKE 'simulation/%'").exists?
        raise Error, 'Legacy identity evidence has an external object key; remove that object and clear the key before retrying.'
      end
      photos = ListingPhoto.where(revision_id: ListingRevision.where(listing_id: Listing.where(donor_id: @account.id)).select(:id))
      photos.each do |photo|
        [photo.original_object_key, photo.sanitized_object_key].compact.each do |key|
          next if key.start_with?('simulation/')
          EquipmentMedia::Photos.path(key) # Refuse unrecognized storage paths.
          if ListingPhoto.where('original_object_key = ? OR sanitized_object_key = ?', key, key).where.not(id: photos.select(:id)).exists?
            raise Error, 'A photo file is shared with another account; review and separate that file before deletion.'
          end
        end
      end
    end

    def apply_review!(review, current)
      review['fields'].zip(current['fields']).each do |field, original|
        next if field['value'] == original['value']
        raise Error, 'Reviewed text must be a string or null.' unless field['value'].nil? || field['value'].is_a?(String)
        record = field['model'].constantize.find(field['id'])
        value = field['value']
        value = Journeys::Support.encrypt(value) if value && field['field'].end_with?('_ciphertext')
        record.update_columns(field['field'] => value)
        if record.is_a?(Agreement)
          record.update_columns(snapshot_sha256: Digest::SHA256.hexdigest(field['value'].to_s))
        end
      end
    end

    def erase_private_records!
      id = @account.id
      contacts = AccountContact.where(account_id: id)
      hmacs = contacts.pluck(:lookup_hmac)
      numbers = contacts.where(kind: 'mobile').map { |c| Journeys::Support.decrypt(c.value_ciphertext) }
      evidence_ids = IdentityEvidence.where(submitted_by: id).pluck(:id)
      upload_ids = IdentityDocumentUpload.where(account_id: id).pluck(:id)
      grants = DisclosureGrant.where(evidence_id: evidence_ids).or(DisclosureGrant.where(consented_by: id))
      SensitiveAccessEvent.where(evidence_id: evidence_ids).or(SensitiveAccessEvent.where(grant_id: grants.select(:id)))
        .or(SensitiveAccessEvent.where(actor_id: id)).delete_all
      grants.delete_all
      BorrowerField.where(evidence_id: evidence_ids).delete_all
      RequestIntent.where(requester_id: id).delete_all
      RequestIntent.where(evidence_id: evidence_ids).update_all(evidence_id: nil)
      IdentityEvidence.where(replaces_evidence_id: evidence_ids).update_all(replaces_evidence_id: nil)
      IdentityEvidence.where(id: evidence_ids).delete_all
      IdentityDocumentUpload.where(account_id: id).delete_all
      jobs = MessageJob.where(recipient_id: id).or(MessageJob.where(contact_id: contacts.select(:id)))
      attempts = MessageAttempt.where(job_id: jobs.select(:id))
      GatewayEvent.where(attempt_id: attempts.select(:id)).delete_all
      attempts.delete_all
      jobs.delete_all
      SmsDelivery.where(recipient_hmac: hmacs).delete_all
      SimulatedSmsMessage.where(recipient: numbers).delete_all
      ConsentEvent.where(account_id: id).delete_all
      challenges = AuthChallenge.where(account_id: id).or(AuthChallenge.where(phone_lookup_hmac: hmacs))
      RegistrationSession.where(challenge_id: challenges.select(:id)).or(RegistrationSession.where(created_account_id: id)).delete_all
      challenges.delete_all
      StaffCredential.where(account_id: id).delete_all
      contacts.delete_all
      [AccountNotice, ActionToken, ActivityEvent, PolicyAcknowledgment, PhotoScreening, ExchangeDisplayPreference].each do |model|
        model.where(account_id: id).delete_all
      end
      AuditEvent.where(actor_id: id).or(AuditEvent.where(entity_id: [id] + evidence_ids + upload_ids)).delete_all
      AccountRole.where(account_id: id).delete_all
      CaseAction.where(actor_id: id).delete_all
      Case.where(reporter_id: id).update_all(details_ciphertext: nil, reporter_id: nil)
      Representation.where(representative_id: id).or(Representation.where(recipient_account_id: id))
        .update_all(subject_reference_ciphertext: nil)
      # Retain counterpart-authored content after review; remove this user's own
      # question/answer/message text irrespective of the review's values.
      EquipmentQuestion.where(requester_id: id).update_all(question_ciphertext: Journeys::Support.encrypt('[Deleted by request]'))
      EquipmentQuestion.where(answered_by: id).update_all(answer_ciphertext: Journeys::Support.encrypt('[Deleted by request]'))
      PrivateMessage.where(sender_id: id).update_all(body_ciphertext: Journeys::Support.encrypt('[Deleted by request]'))
      revisions = ListingRevision.where(listing_id: Listing.where(donor_id: id).select(:id))
      photos = ListingPhoto.where(revision_id: revisions.select(:id))
      keys = photos.pluck(:original_object_key, :sanitized_object_key).flatten.compact.uniq
      photos.delete_all
      keys.each { |key| FileUtils.rm_f(EquipmentMedia::Photos.path(key)) unless key.start_with?('simulation/') }
      # Close, do not claim completion of, unfinished exchanges. Keep counterpart
      # transaction history and identity evidence intact.
      exchanges = Exchange.where(donor_id: id).or(Exchange.where(requester_id: id))
      exchanges.where(state: %w[pending offered reserved loaned]).find_each do |exchange|
        exchange.update!(state: 'closed_unavailable', closed_at: Time.current, closure_reason: 'account_deleted')
        Listing.where(id: exchange.listing_id).update_all(status: 'unavailable')
      end
      Listing.where(donor_id: id).where.not(status: %w[donated withdrawn]).update_all(status: 'withdrawn')
      @account.update!(display_name: 'Deleted account', public_locality: 'Removed', status: 'closed',
        closed_at: Time.current, last_activity_at: nil, last_inactivity_reviewed_at: nil)
      PrivacyDeletionRequest.where(account_id: id).delete_all
      # No actor-linked deletion audit is written: the user explicitly requested
      # removal of their audit trail. The operator receives only success/failure.
    end
  end
end
