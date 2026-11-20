class IdentityDocumentsController < AuthenticatedController
  before_action -> { Journeys::Support.active!(current_account) }
  rescue_from Journeys::Error, with: :scan_error
  def create
    raise Journeys::Error, 'Consent to document processing is required.' unless params[:processing_consent] == '1'
    workflow = Journeys::Workflow.new(current_account)
    workflow.member!
    listing = Listing.find(params[:id])
    upload = IdentityDocuments::Intake.scan!(current_account, listing, params[:identity_document], params[:document_kind])
    redirect_to identity_document_path(upload, retry_id: params[:retry_id])
  end
  def show
    @upload = IdentityDocumentUpload.find_by!(id: params[:id], account_id: current_account.id)
    raise Journeys::Error, 'This scan has expired. Please upload a new document.' if @upload.purge_due_at <= Time.current
    raise Journeys::Error, 'This document could not be extracted. Please upload another.' unless %w[extracted confirmed].include?(@upload.state)
    @fields = @upload.extracted_fields
  end
  def image
    upload = IdentityDocumentUpload.find(params[:id])
    moderator = AccountRole.exists?(account_id: current_account.id, role: 'moderator')
    raise ActiveRecord::RecordNotFound unless upload.account_id == current_account.id || moderator
    Privacy::ExchangeRetention.apply!(Exchange.find(upload.exchange_id)) if upload.exchange_id
    upload.reload
    raise ActiveRecord::RecordNotFound unless upload.purge_due_at > Time.current && upload.image_ciphertext
    Journeys::Support.audit(current_account, 'identity_document_viewed', upload)
    response.headers['X-Content-Type-Options'] = 'nosniff'
    send_data IdentityDocuments::Vault.decrypt(upload.image_ciphertext), type: 'image/jpeg', disposition: 'inline', filename: 'identity-document.jpg'
  end
  def confirm
    raise Journeys::Error, 'Confirm that the extracted information matches your document.' unless params[:confirmed] == '1'
    upload = IdentityDocumentUpload.find_by!(id: params[:id], account_id: current_account.id)
    exchange = upload.with_lock do
      if upload.exchange_id
        Exchange.find(upload.exchange_id)
      else
        raise Journeys::Error, 'This scan is not available for confirmation. Please upload again.' unless upload.state == 'extracted' && upload.purge_due_at > Time.current
        listing = Listing.find(upload.listing_id)
        raise Journeys::Error, 'The listing changed. Please start your request again.' unless listing.approved_revision_id == upload.revision_id
        if params.key?(:first_name) || params.key?(:last_name)
          fields = upload.extracted_fields
          first = params[:first_name].to_s.squish
          last = params[:last_name].to_s.squish
          original = [fields['first_name'], fields['last_name']].join(' ').squish
          unless first.present? && last.present? && first.length <= 500 && last.length <= 500
            raise Journeys::Error, 'Enter both first and last name as shown on your document (up to 500 characters each).'
          end
          fields['_extracted_name'] ||= { 'first_name' => fields['first_name'], 'last_name' => fields['last_name'] }
          fields.merge!('first_name' => first, 'last_name' => last)
          upload.update!(fields_ciphertext: IdentityDocuments::Vault.encrypt(fields.to_json))
        end
        result = Journeys::Workflow.new(current_account).request!(listing.id, consent: params[:consent], outcome: 'pass', retry_id: params[:retry_id], document_upload: upload)
        upload.update!(state: 'confirmed', confirmed_at: Time.current, exchange_id: result.id)
        result
      end
    end
    redirect_to transaction_path(exchange), notice: 'Your document-extracted details are confirmed. The request was sent to the donor.'
  end
  private
  def scan_error(error)
    upload = IdentityDocumentUpload.find_by(id: params[:id], account_id: current_account.id) unless action_name == 'create'
    destination = upload && action_name == 'confirm' && upload.state == 'extracted' && upload.purge_due_at > Time.current ? identity_document_path(upload, retry_id: params[:retry_id]) : upload ? new_equipment_request_path(upload.listing_id) : action_name == 'create' ? new_equipment_request_path(params[:id]) : activity_path
    redirect_to destination, alert: error.message
  end
end
