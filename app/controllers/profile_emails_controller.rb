class ProfileEmailsController < ApplicationController
  def show
    @token = params[:token]
    raise ActiveRecord::RecordNotFound unless UpdateProfile.resolve(@token)
  end

  def update
    UpdateProfile.confirm(params[:token])
    reset_session
    redirect_to new_session_path, notice: "Email updated. Sign in with your new email address."
  end
end
