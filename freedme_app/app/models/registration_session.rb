# PostgreSQL v0.2 owns constraints, lifecycle triggers and UUID defaults.
class RegistrationSession < ApplicationRecord
  self.table_name = "freedme.registration_sessions"
  self.primary_key = "id"
  belongs_to :challenge, class_name: "AuthChallenge", foreign_key: "challenge_id", primary_key: "id", optional: false
  belongs_to :listing, class_name: "Listing", foreign_key: "listing_id", primary_key: "id", optional: true
  belongs_to :created_account, class_name: "Account", foreign_key: "created_account_id", primary_key: "id", optional: true
end
