module Staff
  class RequestsController < BaseController
    before_action -> { authorize!("distribution.manage") }
    def index
      @requests = EquipmentRequest.order(submitted_at: :desc).limit(100)
    end
    def show
      @equipment_request = EquipmentRequest.find(params[:id])
    end
    def update
      Workflow.run do
        Workflow.authorize!(current_user, "distribution.manage")
        record = EquipmentRequest.find(params[:id])
        raise Workflow::Error, "Only submitted requests can be reviewed." unless %w[submitted under_review].include?(record.status)
        raise Workflow::Error, "Choose an approval decision." unless %w[approved rejected].include?(params[:status])
        raise Workflow::Error, "Provide a rejection reason." if params[:status] == "rejected" && params[:reason].blank?
        record.update!(status: params[:status], rejection_reason: params[:reason], reviewed_by: current_user.id, reviewed_at: Time.current)
        Audit.record!(current_user, "request.#{record.status}", record)
      end
      redirect_to staff_request_path(params[:id]), notice: "Review saved."
    end
    def reserve
      ReserveEquipment.call(current_user, params[:id])
      redirect_to staff_request_path(params[:id]), notice: "Equipment reserved."
    end
    def cancel_reservation
      Workflow.run do
        Workflow.authorize!(current_user, "distribution.manage")
        reservation = Reservation.where(request_id: params[:id], status: "active").find(params[:reservation_id])
        reservation.update!(status: "cancelled", closed_by: current_user.id)
        Audit.record!(current_user, "reservation.cancelled", reservation)
      end
      redirect_to staff_request_path(params[:id]), notice: "Reservation cancelled."
    end
    def release
      ReleaseEquipment.call(current_user, params[:id], params[:reservation_id], params[:signature], params[:condition])
      redirect_to staff_request_path(params[:id]), notice: "Equipment distributed."
    end
  end
end
