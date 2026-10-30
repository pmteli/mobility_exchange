# PostgreSQL v0.2 owns constraints, lifecycle triggers and UUID defaults.
class ServiceArea < ApplicationRecord
  self.table_name = "freedme.service_areas"
  self.primary_key = "id"
  belongs_to :policy, class_name: "PolicyVersion", foreign_key: "policy_id", primary_key: "id", optional: false
end
