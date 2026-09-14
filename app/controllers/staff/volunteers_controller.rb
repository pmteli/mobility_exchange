module Staff
  class VolunteersController < BaseController
    before_action -> { authorize!("users.manage") }
    def index
      @volunteers = Volunteer.includes(:user).limit(100)
    end
    def update
      Workflow.run do
        Workflow.authorize!(current_user, "users.manage")
        volunteer = Volunteer.find(params[:id])
        raise Workflow::Error, "Invalid decision." unless %w[approved rejected inactive].include?(params[:status])
        volunteer.update!(approval_status: params[:status], approved_by: current_user.id, approved_at: Time.current)
        if params[:status] == "approved"
          UserRole.find_or_create_by!(user_id: volunteer.user_id, role_id: "volunteer") { |role| role.assigned_by = current_user.id }
        else
          UserRole.where(user_id: volunteer.user_id, role_id: "volunteer").delete_all
          ShiftSignup.where(volunteer_id: volunteer.user_id, status: "signed_up").update_all(status: "cancelled")
        end
        Audit.record!(current_user, "volunteer.#{params[:status]}", volunteer)
      end
      redirect_to staff_volunteers_path, notice: "Volunteer updated."
    end
  end
end
