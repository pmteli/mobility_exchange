class SubmitDonation
  def self.call(actor, contact, item_attributes, photos: [])
    prepared = DonationPhotos.prepare(photos)
    Workflow.run do
      EquipmentType.where(active: true).find(item_attributes[:type_id])
      raise Workflow::Error, "Enter an equipment name and quantity between 1 and 20." if item_attributes[:name].blank? || !(1..20).cover?(item_attributes[:quantity].to_i)
      donor = Donor.find_or_initialize_by(user_id: actor.id)
      donor.assign_attributes(contact.slice(:phone, :city, :region, :postal_code))
      donor.assign_attributes(first_name: actor.first_name, last_name: actor.last_name, email: actor.email)
      donor.save!
      intake = IntakeSubmission.create!(reference_number: Workflow.reference("DON"), donor_id: donor.id, submitted_by: actor.id, status: "submitted", submitted_at: Time.current)
      item = IntakeItem.create!(item_attributes.merge(intake_id: intake.id))
      prepared.each do |attributes|
        file = PrivateEvidence.persist!(attributes, actor)
        IntakeItemFile.create!(intake_item_id: item.id, file_id: file.id, purpose: "other")
      end
      Audit.record!(actor, "donation.submitted", intake)
      intake
    end
  rescue StandardError
    DonationPhotos.cleanup(prepared || [])
    raise
  end
end
