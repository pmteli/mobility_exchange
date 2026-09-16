class IntakeSubmission < MobilityRecord
  self.table_name = "mobility_exchange.intake_submissions"
  self.primary_key = "id"
  belongs_to :donor
  has_many :intake_items, foreign_key: :intake_id
  has_many :signed_donor_certifications, foreign_key: :intake_id

end
