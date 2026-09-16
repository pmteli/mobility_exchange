class DonationsController < ApplicationController
  before_action :require_login
  before_action :load_donation, only: [:show, :sign, :book]
  def new
    @types = EquipmentType.where(active: true).order(:name)
  end
  def create
    donation = SubmitDonation.call(current_user, params.require(:contact).permit(:phone, :city, :region, :postal_code).to_h.symbolize_keys, params.require(:item).permit(:type_id, :name, :manufacturer, :model, :condition, :quantity, :description).to_h.symbolize_keys)
    redirect_to donation_path(donation), notice: "Donation submitted for review."
  end
  def show
    @legal = LegalDocumentVersion.find_by(id: ActiveLegalDocument.find_by(kind: "donor_certification")&.version_id)
    @slots = AppointmentSlot.where(kind: "dropoff", cancelled_at: nil).where("starts_at > ?", Time.current).includes(:location).order(:starts_at).limit(50)
  end
  def sign
    SignDocument.call(current_user, @donation, params[:version_id], params[:signature], params[:consent])
    redirect_to donation_path(@donation), notice: "Certification signed and stored."
  end
  def book
    BookAppointment.call(current_user, @donation, params[:slot_id])
    redirect_to donation_path(@donation), notice: "Drop-off booked."
  end
  private
  def load_donation
    @donation = IntakeSubmission.where(submitted_by: current_user.id).find(params[:id])
  end
end
