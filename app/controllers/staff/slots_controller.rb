module Staff
  class SlotsController < BaseController
    before_action -> { authorize!("distribution.manage") }
    def index
      @slots = AppointmentSlot.includes(:location).order(starts_at: :desc).limit(100)
    end
    def new
      @record = AppointmentSlot.new
    end
    def create
      Workflow.run do
        Workflow.authorize!(current_user, "distribution.manage")
        attrs = params.require(:schedule).permit(:kind, :location_id, :starts_at, :ends_at, :capacity).to_h.symbolize_keys
        record = AppointmentSlot.create!(attrs.merge(created_by: current_user.id))
        Audit.record!(current_user, "slots.created", record)
      end
      redirect_to staff_slots_path, notice: "Schedule created."
    end
    def update
      Workflow.run do
        Workflow.authorize!(current_user, "distribution.manage")
        record = AppointmentSlot.find(params[:id])
        record.update!(cancelled_at: Time.current)
        Audit.record!(current_user, "slots.cancelled", record)
      end
      redirect_to staff_slots_path, notice: "Schedule cancelled."
    end
  end
end
