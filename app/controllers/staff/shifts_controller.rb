module Staff
  class ShiftsController < BaseController
    before_action -> { authorize!("shifts.manage") }
    def index
      @shifts = VolunteerShift.includes(:location).order(starts_at: :desc).limit(100)
    end
    def new
      @record = VolunteerShift.new
    end
    def create
      Workflow.run do
        Workflow.authorize!(current_user, "shifts.manage")
        attrs = params.require(:schedule).permit(:activity, :notes, :location_id, :starts_at, :ends_at, :capacity).to_h.symbolize_keys
        record = VolunteerShift.create!(attrs.merge(created_by: current_user.id))
        Audit.record!(current_user, "shifts.created", record)
      end
      redirect_to staff_shifts_path, notice: "Schedule created."
    end
    def update
      Workflow.run do
        Workflow.authorize!(current_user, "shifts.manage")
        record = VolunteerShift.find(params[:id])
        record.update!(cancelled_at: Time.current)
        Audit.record!(current_user, "shifts.cancelled", record)
      end
      redirect_to staff_shifts_path, notice: "Schedule cancelled."
    end
  end
end
