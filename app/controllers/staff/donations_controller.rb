module Staff
  class DonationsController < BaseController
    before_action -> { authorize!("intake.review") }
    def index
      @donations = IntakeSubmission.order(created_at: :desc).limit(100)
    end
    def show
      @donation = IntakeSubmission.find(params[:id])
    end
    def update
      Workflow.run do
        Workflow.authorize!(current_user, "intake.review")
        record = IntakeSubmission.find(params[:id])
        raise Workflow::Error, "Only submitted donations can be reviewed." unless %w[submitted under_review].include?(record.status)
        raise Workflow::Error, "Choose an approval decision." unless %w[approved rejected].include?(params[:status])
        raise Workflow::Error, "Provide a rejection reason." if params[:status] == "rejected" && params[:reason].blank?
        record.update!(status: params[:status], rejection_reason: params[:reason], reviewed_by: current_user.id, reviewed_at: Time.current)
        Audit.record!(current_user, "donation.#{record.status}", record)
      end
      redirect_to staff_donation_path(params[:id]), notice: "Review saved."
    end
    def receive_item
      Workflow.run do
        Workflow.authorize!(current_user, "inventory.write")
        intake = IntakeSubmission.find(params[:id])
        raise Workflow::Error, "Approve and sign this donation first." unless %w[approved scheduled received].include?(intake.status) && intake.signed_donor_certifications.exists?
        line = intake.intake_items.find(params[:item_id])
        raise Workflow::Error, "All units for this line have already been received." if Equipment.where(intake_item_id: line.id).count >= line.quantity
        location = Location.where(status: "active").find(params[:location_id])
        record = Equipment.create!(inventory_number: Workflow.reference("MX"), type_id: line.type_id, name: line.name, manufacturer: line.manufacturer, model: line.model, description: line.description, condition: line.condition, acquisition_kind: "donation", intake_item_id: line.id, location_id: location.id, received_at: Time.current, created_by: current_user.id, updated_by: current_user.id)
        complete = intake.intake_items.all? { |item| Equipment.where(intake_item_id: item.id).count >= item.quantity }
        intake.update!(status: complete ? "completed" : "received")
        Appointment.where(intake_id: intake.id, status: "booked").update_all(status: "completed") if complete
        Audit.record!(current_user, "donation.unit_received", record)
      end
      redirect_to staff_donation_path(params[:id]), notice: "One unit added to inventory."
    end
  end
end
