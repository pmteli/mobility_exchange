class EquipmentController < ApplicationController
  def index
    @categories = Category.order(:name)
    @equipment = EquipmentCatalog.call(**params.permit(:query, :category_id, :offer_kind, :page).to_h.symbolize_keys)
    @page = params[:page].to_i.clamp(1, 1000)
  end
  def show
    @listing = Listing.find(params[:id])
    @moderator_view = current_account && AccountRole.exists?(account_id: current_account.id, role: "moderator")
    authorized = current_account && (@listing.donor_id == current_account.id || @moderator_view || Exchange.where(listing_id: @listing.id, requester_id: current_account.id).exists? || EquipmentQuestion.where(listing_id: @listing.id, requester_id: current_account.id).exists?)
    raise ActiveRecord::RecordNotFound unless AvailableListingCard.exists?(id: @listing.id) || authorized
    @item = ListingRevision.find(@listing.current_revision_id)
    @donor_name = @listing.donor.display_name
    @held = Exchange.where(listing_id: @listing.id, state: Journeys::Workflow::ACTIVE).exists?
  end
end
