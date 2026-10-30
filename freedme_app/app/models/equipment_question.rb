# PostgreSQL v0.2 owns constraints, lifecycle triggers and UUID defaults.
class EquipmentQuestion < ApplicationRecord
  self.table_name = "freedme.equipment_questions"
  self.primary_key = "id"
  belongs_to :requester, class_name: "Account", foreign_key: "requester_id", primary_key: "id", optional: false
  belongs_to :answered_by_account, class_name: "Account", foreign_key: "answered_by", primary_key: "id", optional: true
end
