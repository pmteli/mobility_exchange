# PostgreSQL v0.2 owns constraints, lifecycle triggers and UUID defaults.
class Resource < ApplicationRecord
  self.table_name = "freedme.resources"
  self.primary_key = "id"
  belongs_to :reviewer, class_name: "Account", foreign_key: "reviewer_id", primary_key: "id", optional: true
end
