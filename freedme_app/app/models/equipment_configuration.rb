# PostgreSQL v0.2 owns constraints, lifecycle triggers and UUID defaults.
class EquipmentConfiguration < ApplicationRecord
  self.table_name = "freedme.equipment_configurations"
  self.primary_key = "id"
  belongs_to :category, class_name: "Category", foreign_key: "category_id", primary_key: "id", optional: false
  belongs_to :policy, class_name: "PolicyVersion", foreign_key: "policy_id", primary_key: "id", optional: false
  belongs_to :guidance_policy, class_name: "PolicyVersion", foreign_key: "guidance_policy_id", primary_key: "id", optional: true
end
