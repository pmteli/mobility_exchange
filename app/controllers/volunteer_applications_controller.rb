class VolunteerApplicationsController < ApplicationController
  before_action :require_login
  def new; end
  def create
    Workflow.run do
      raise Workflow::Error, "You already have a volunteer application." if Volunteer.exists?(user_id: current_user.id)
      volunteer = Volunteer.create!(user_id: current_user.id, skills: params[:skills].to_s.first(2000))
      Audit.record!(current_user, "volunteer.applied", volunteer)
    end
    redirect_to account_path, notice: "Volunteer application submitted."
  end
end
