class EquipmentRequestsController < ApplicationController
  before_action :require_login
  before_action :load_request, only: [:show, :sign, :book]
  def new
    @item = CatalogItem.find(params[:equipment_id])
  end
  def create
    result = SubmitRequest.call(current_user, params[:equipment_id], params.require(:contact).permit(:phone, :address_line1, :city, :region, :postal_code).to_h.symbolize_keys)
    redirect_to equipment_request_path(result), notice: "Request submitted. The team will review availability."
  end
  def show
    @legal = LegalDocumentVersion.find_by(id: ActiveLegalDocument.find_by(kind: "recipient_waiver")&.version_id)
    location_ids = Equipment.where(id: @equipment_request.reservations.where(status: "active").select(:equipment_id)).select(:location_id)
    @slots = AppointmentSlot.where(kind: "pickup", cancelled_at: nil, location_id: location_ids).where("starts_at > ?", Time.current).includes(:location).order(:starts_at).limit(50)
  end
  def sign
    SignDocument.call(current_user, @equipment_request, params[:version_id], params[:signature], params[:consent])
    redirect_to equipment_request_path(@equipment_request), notice: "Waiver signed and stored."
  end
  def book
    BookAppointment.call(current_user, @equipment_request, params[:slot_id])
    redirect_to equipment_request_path(@equipment_request), notice: "Pickup booked."
  end
  private
  def load_request
    @equipment_request = EquipmentRequest.where(requested_by: current_user.id).find(params[:id])
  end
end
