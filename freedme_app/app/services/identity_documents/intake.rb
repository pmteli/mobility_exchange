require 'tempfile'
require 'timeout'
module IdentityDocuments
  class Intake
    def self.enabled?
      ENV['TEXTRACT_ENABLED'] == 'true'
    end
    def self.scan!(actor, listing, upload, kind)
      raise Journeys::Error, 'Document scanning is not configured yet.' unless enabled?
      Journeys::Support.active!(actor, listing)
      raise Journeys::Error, 'You cannot request your own equipment.' if listing.donor_id == actor.id
      raise Journeys::Error, 'This item is no longer available.' unless listing.status == 'available'
      raise Journeys::Error, 'Choose a document type.' unless %w[utility_bill government_id].include?(kind)
      unless upload.respond_to?(:tempfile) && upload.size.between?(1, 20.megabytes)
        raise Journeys::Error, 'Upload one JPEG, PNG or single-page PDF, up to 20 MB.'
      end
      record = actor.with_lock do
        raise Journeys::Error, 'Document scan limit reached. Try again in an hour.' if IdentityDocumentUpload.where(account_id: actor.id).where('created_at > ?', 1.hour.ago).count >= 10
        IdentityDocumentUpload.create!(account: actor, listing: listing, revision_id: listing.approved_revision_id, document_kind: kind, purge_due_at: 7.days.from_now)
      end
      Tempfile.create(['identity-scan', '.jpg']) do |clean|
        File.chmod(0600, clean.path)
        pid = Process.spawn('python3', Rails.root.join('script/sanitize_identity_document.py').to_s, upload.tempfile.path, clean.path, out: File::NULL, err: File::NULL)
        begin
          _, status = Timeout.timeout(40) { Process.wait2(pid) }
        rescue Timeout::Error
          Process.kill('KILL', pid) rescue nil
          Process.wait(pid) rescue nil
          raise Journeys::Error, 'Image processing timed out. Please try a smaller image.'
        end
        raise Journeys::Error, 'Upload a single-page PDF containing your name and address. Multi-page PDFs are not supported.' if status.exitstatus == 2
        raise Journeys::Error, 'Upload an unlocked PDF. Password-protected PDFs cannot be scanned.' if status.exitstatus == 3
        raise Journeys::Error, 'Use a clear single-page PDF or non-animated JPEG or PNG image (up to 50 megapixels).' unless status.success? && File.size(clean.path).between?(1,10_000_000)
        bytes = File.binread(clean.path)
        record.update!(image_ciphertext: Vault.encrypt(bytes))
        fields = Extractor.new.extract(bytes, kind)
        record.update!(fields_ciphertext: Vault.encrypt(fields.to_json), state: 'extracted')
      end
      record
    rescue Aws::Textract::Errors::ServiceError, Seahorse::Client::NetworkingError, Aws::Errors::MissingCredentialsError
      record&.update!(state: 'failed')
      raise Journeys::Error, 'Document scanning is temporarily unavailable. No request was sent. Please try again later.'
    rescue StandardError
      record&.update!(state: 'failed')
      raise
    ensure
      upload.tempfile.close! if upload.respond_to?(:tempfile) && upload.tempfile.respond_to?(:close!)
    end
  end
end
