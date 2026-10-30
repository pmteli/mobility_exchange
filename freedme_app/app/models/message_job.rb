# PostgreSQL v0.2 owns constraints, lifecycle triggers and UUID defaults.
class MessageJob < ApplicationRecord
  self.table_name = "freedme.message_jobs"
  self.primary_key = "id"
  belongs_to :recipient, class_name: "Account", foreign_key: "recipient_id", primary_key: "id", optional: false
  belongs_to :contact, class_name: "AccountContact", foreign_key: "contact_id", primary_key: "id", optional: false
  belongs_to :exchange, class_name: "Exchange", foreign_key: "exchange_id", primary_key: "id", optional: true
  belongs_to :followup_cycle, class_name: "FollowupCycle", foreign_key: "followup_cycle_id", primary_key: "id", optional: true
  belongs_to :question, class_name: "EquipmentQuestion", foreign_key: "question_id", primary_key: "id", optional: true
  belongs_to :listing, class_name: "Listing", foreign_key: "listing_id", primary_key: "id", optional: true
end
