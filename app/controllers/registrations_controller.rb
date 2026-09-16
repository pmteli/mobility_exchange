class RegistrationsController < ApplicationController
  rate_limit to: 5, within: 1.hour, only: :create
  def new; end
  def create
    Signup.call(params.permit(:first_name, :last_name, :email, :password, :password_confirmation, community_roles: []).to_h.symbolize_keys)
    redirect_to new_session_path, notice: "Account created. Check your email to verify your address before signing in."
  rescue Workflow::Error => error
    flash.now[:alert] = error.message
    render :new, status: :unprocessable_entity
  end
end
