class DonationPhotosController < ApplicationController
  before_action :require_login

  def show
    donation = if allowed?("intake.review")
      IntakeSubmission.find(params[:donation_id])
    else
      IntakeSubmission.where(submitted_by: current_user.id).find(params[:donation_id])
    end
    links = IntakeItemFile.where(intake_item_id: donation.intake_items.select(:id))
    file = StoredFile.where(id: links.select(:file_id), mime_type: "image/jpeg", scan_status: "clean", deleted_at: nil).find(params[:id])
    response.headers["X-Content-Type-Options"] = "nosniff"
    send_file PrivateEvidence.path(file), type: "image/jpeg", disposition: "inline", filename: "equipment-photo.jpg"
  end
end
