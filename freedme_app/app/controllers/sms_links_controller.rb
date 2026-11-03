class SmsLinksController < ApplicationController
  def show
    destination = Integrations::SmsLinks::DESTINATIONS[params[:code]]
    return head :not_found unless destination

    response.headers["Cache-Control"] = "no-store"
    if destination.start_with?("/activity") && !current_account
      session[:return_to] = destination
      redirect_to sign_in_path
    else
      redirect_to destination
    end
  end
end
