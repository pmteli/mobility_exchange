class EquipmentPhotosController < ApplicationController
  def show
    photo = ListingPhoto.find(params[:id])
    listing = Listing.find(photo.revision.listing_id)
    owner_or_staff = current_account && (listing.donor_id == current_account.id || AccountRole.exists?(account_id: current_account.id, role: "moderator"))
    published = photo.state == "approved" && photo.revision_id == listing.approved_revision_id && AvailableListingCard.exists?(id: listing.id)
    participant = current_account && photo.state == "approved" && photo.revision_id == listing.approved_revision_id && Exchange.where(listing_id: listing.id, requester_id: current_account.id).exists?
    raise ActiveRecord::RecordNotFound unless owner_or_staff || published || participant
    path = EquipmentMedia::Photos.path(photo.sanitized_object_key)
    raise ActiveRecord::RecordNotFound unless path.file?
    response.headers["Cache-Control"] = "private, no-store"
    response.headers["X-Content-Type-Options"] = "nosniff"
    send_file path, type: "image/jpeg", disposition: "inline", filename: "equipment-photo.jpg"
  end
end
