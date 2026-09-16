class AccountsController < ApplicationController
  before_action :require_login
  def show
    @requests = EquipmentRequest.where(requested_by: current_user.id).order(submitted_at: :desc).limit(100)
    @donations = IntakeSubmission.where(submitted_by: current_user.id).order(created_at: :desc).limit(100)
  end
end
