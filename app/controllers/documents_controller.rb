class DocumentsController < ApplicationController
  before_action :require_login
  def show
    file = StoredFile.find(params[:id])
    waiver = SignedWaiver.find_by(signed_pdf_file_id: file.id)
    certification = SignedDonorCertification.find_by(signed_pdf_file_id: file.id)
    owner = waiver && EquipmentRequest.exists?(id: waiver.request_id, requested_by: current_user.id)
    owner ||= certification && IntakeSubmission.exists?(id: certification.intake_id, submitted_by: current_user.id)
    staff_access = (waiver || certification) && current_user.admin?
    raise ActiveRecord::RecordNotFound unless owner || staff_access
    response.headers["Cache-Control"] = "private, no-store"
    send_file PrivateEvidence.path(file), filename: file.original_filename, type: file.mime_type, disposition: "attachment"
  end
end
