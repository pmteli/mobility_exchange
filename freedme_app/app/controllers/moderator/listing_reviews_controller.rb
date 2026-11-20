class Moderator::ListingReviewsController < ApplicationController
  def show
    unless current_account
      session[:return_to] = request.path
      redirect_to staff_sign_in_path
      return
    end
    unless AccountRole.exists?(account_id: current_account.id, role: "moderator")
      head :forbidden
      return
    end
    listing = Listing.find(params[:id])
    if listing.status == "pending_review"
      redirect_to activity_path(review: listing.id, anchor: "panel-review")
    else
      redirect_to equipment_path(listing), notice: "This item is no longer awaiting review."
    end
  end
end
