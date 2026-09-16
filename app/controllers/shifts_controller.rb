class ShiftsController < ApplicationController
  before_action :require_login
  def index
    @shifts = VolunteerShift.where(cancelled_at: nil).where("starts_at > ?", Time.current).includes(:location).order(:starts_at).limit(100)
    @signups = ShiftSignup.where(volunteer_id: current_user.id, status: "signed_up").pluck(:shift_id)
  end
  def join
    Workflow.run do
      Workflow.authorize!(current_user, "shifts.signup")
      shift = VolunteerShift.where("starts_at > ?", Time.current).find(params[:id])
      signup = ShiftSignup.find_or_initialize_by(shift_id: shift.id, volunteer_id: current_user.id)
      signup.update!(status: "signed_up")
      Audit.record!(current_user, "shift.joined", shift)
    end
    redirect_to shifts_path, notice: "You are signed up."
  end
  def leave
    Workflow.run do
      signup = ShiftSignup.find_by!(shift_id: params[:id], volunteer_id: current_user.id)
      raise Workflow::Error, "Only upcoming shifts can be cancelled." unless VolunteerShift.find(params[:id]).starts_at.future?
      signup.update!(status: "cancelled")
    end
    redirect_to shifts_path, notice: "Shift signup cancelled."
  end
end
