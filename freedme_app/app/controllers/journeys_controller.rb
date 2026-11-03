class JourneysController < AuthenticatedController
  before_action :prepare_workflow
  rescue_from Journeys::Error, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique, ActiveRecord::StatementInvalid, with: :workflow_error
  def index
    @roles = AccountRole.where(account_id: current_account.id).pluck(:role)
    @listings = Listing.where(donor_id: current_account.id).newest_first
    @exchanges = Exchange.where("donor_id=? OR requester_id=?", current_account.id, current_account.id).order(requested_at: :desc)
    @exchanges = @exchanges.where.not(id: ExchangeDisplayPreference.where(account_id: current_account.id).where.not(hidden_at: nil).select(:exchange_id))
    @questions = EquipmentQuestion.where("donor_id=? OR requester_id=?", current_account.id, current_account.id).order(asked_at: :desc).group_by(&:listing_id)
    @reviews = Listing.where(status: "pending_review").newest_first if @roles.include?("moderator")
    @identity_uploads = IdentityDocumentUpload.order(created_at: :desc).limit(50) if @roles.include?("moderator")
    @tasks = ModeratorTask.order(due_at: :asc) if @roles.include?("moderator")
    contact = AccountContact.find_by!(account_id: current_account.id, kind: "mobile", revoked_at: nil)
    @messages = SimulatedSmsMessage.where(recipient: Journeys::Support.decrypt(contact.value_ciphertext)).where.not(template_code: "sign_in_otp").order(created_at: :desc).limit(30)
  end
  def new_listing
    @categories = Category.order(:name)
    @data = { "public_locality" => current_account.public_locality, "offer_kind" => "gift" }
    render :listing_form
  end
  def edit_listing
    @listing = @workflow.listing!(params[:id])
    @data = ListingRevision.find(@listing.current_revision_id).attributes
    @data["category_id"] = EquipmentConfiguration.find(@data["configuration_id"]).category_id
    @categories = Category.order(:name)
    render :listing_form
  end
  def save_listing
    @listing = @workflow.save_listing!(listing_params.to_h, id: params[:id])
    redirect_to activity_path(anchor: "panel-inventory"), notice: "Thank you for offering your equipment to a neighbor. Your listing is under review. You will be notified when it is published. (Simulated SMS recorded.)"
  rescue Journeys::Error, ActiveRecord::RecordInvalid => error
    @categories = Category.order(:name)
    @data = listing_params.to_h
    @listing = @workflow.listing!(params[:id]) if params[:id]
    flash.now[:alert] = error.message
    render :listing_form, status: :unprocessable_entity
  end
  def review
    @workflow.review!(params[:id], params[:decision], params[:reason])
    redirect_to activity_path, notice: "Review saved. A simulated SMS was recorded."
  end
  def request_form
    @listing = Listing.find(params[:id])
    @revision = ListingRevision.find(@listing.current_revision_id)
  end
  def create_request
    result = @workflow.request!(params[:id], consent: params[:consent], outcome: params[:outcome], retry_id: params[:retry_id])
    if result.is_a?(RequestIntent)
      redirect_to new_equipment_request_path(params[:id]), alert: "We are unable to verify your identity or location with the document you uploaded. Please upload a utility bill or a government issued id showing your name and address to verify your identity and location. (Simulated failure; no document was uploaded.)"
    else
      redirect_to transaction_path(result), notice: "Simulated identity verified. Your request was sent to the donor; simulated SMS recorded."
    end
  end
  def transaction
    @exchange = @workflow.exchange!(params[:id])
    @revision = ListingRevision.find(@exchange.revision_id)
    @proposal = HandoffProposal.where(exchange_id: @exchange.id).order(revision: :desc).first
    if @exchange.donor_id == current_account.id && %w[pending offered reserved].include?(@exchange.state)
      sql = ApplicationRecord.sanitize_sql_array(["SELECT field_name, encode(value_ciphertext, 'base64') AS ciphertext FROM freedme.read_donor_identity(?, ?)", current_account.id, @exchange.id])
      # The database function audits access and returns only granted name/ZIP fields.
      confirmed_upload = IdentityDocumentUpload.find_by(exchange_id: @exchange.id, state: 'confirmed')
      @document_confirmed = confirmed_upload.present?
      @name_corrected = confirmed_upload&.name_corrected?
      @identity = ApplicationRecord.connection.select_all(sql).to_a.to_h { |row| [row["field_name"], Journeys::Support.decrypt(Base64.decode64(row["ciphertext"]))] }
    end
  end
  def change
    @workflow.change!(params[:id], params[:event], params.permit(:meeting_at, :location, :proposal_id).to_h.symbolize_keys)
    redirect_to transaction_path(params[:id]), notice: "Action saved. Notifications are simulated."
  end
  def reopen
    @workflow.reopen!(params[:id], params[:confirmed])
    redirect_to activity_path, notice: "Availability confirmed. The item is available again."
  end
  def ask
    @workflow.ask!(params[:id], params[:question])
    redirect_to activity_path, notice: "Question saved. The donor has a simulated SMS notification."
  end
  def answer
    @workflow.answer!(params[:id], params[:answer])
    redirect_to activity_path, notice: "Answer saved. The recipient has a simulated SMS notification."
  end
  def resolve_task
    @workflow.staff!
    task = ModeratorTask.find(params[:id])
    task.with_lock do
      raise Journeys::Error, "Task is already closed." unless %w[open in_progress].include?(task.state)
      raise Journeys::Error, "Select a follow-up outcome." unless %w[handoff_confirmed not_handed_off unable_to_reach cancelled].include?(params[:outcome])
      raise Journeys::Error, "Record the contact attempts and outcome." if params[:notes].to_s.strip.empty?
      task.update!(state: "resolved", assigned_to: current_account.id, outcome: params[:outcome], resolved_at: Time.current,
        donor_contacted_at: params[:donor_contacted] == "1" ? Time.current : nil,
        recipient_contacted_at: params[:recipient_contacted] == "1" ? Time.current : nil,
        notes_ciphertext: Journeys::Support.encrypt(params[:notes]))
      Journeys::Support.audit(current_account, "followup_resolved", task)
    end
    redirect_to activity_path, notice: "Follow-up outcome recorded; equipment state was not changed."
  end
  private
  def prepare_workflow
    @workflow = Journeys::Workflow.new(current_account)
    Journeys::Deadlines.run!
  end
  def listing_params
    params.require(:listing).permit(:title, :description, :category_id, :public_locality, :condition_code, :offer_kind, :loan_until,
      :no_missing_parts_affirmed, :fully_functional_affirmed, :truthfulness_affirmed, photos: [], remove_photo_ids: [])
  end
  def workflow_error(error)
    message = error.is_a?(ActiveRecord::StatementInvalid) ? "This action is no longer valid. Reload the page and review the current status." : error.message
    redirect_to activity_path, alert: message
  end
end
