class AccountsController < ApplicationController
  before_action :require_login
  def edit
    @profile = current_user
    contact = @profile.recipient || @profile.donor
    if contact
      %w[address_line1 address_line2 city region postal_code].each do |field|
        @profile[field] ||= contact[field]
      end
    end
  end

  def update
    attributes = params.require(:user).permit(*UpdateProfile::FIELDS, :email).to_h.symbolize_keys
    @profile = current_user
    UpdateProfile.call(@profile, attributes, current_password: params[:current_password])
    redirect_to account_path, notice: @profile.pending_email ? "Profile saved. Confirm the link sent to your new email. Your current email still works until then." : "Profile saved."
  rescue Workflow::Error, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => error
    @profile.assign_attributes(attributes.slice(*UpdateProfile::FIELDS))
    @submitted_email = attributes[:email]
    @profile_error = error.is_a?(ActiveRecord::RecordNotUnique) ? "This email address is already in use." : error.message
    render :edit, status: :unprocessable_entity
  end
  def show
    @requests = EquipmentRequest.where(requested_by: current_user.id).order(submitted_at: :desc).limit(100)
    @donations = IntakeSubmission.where(submitted_by: current_user.id).order(created_at: :desc).limit(100)
  end
end
