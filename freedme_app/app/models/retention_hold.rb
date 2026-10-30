# PostgreSQL v0.2 owns constraints, lifecycle triggers and UUID defaults.
class RetentionHold < ApplicationRecord
  self.table_name = "freedme.retention_holds"
  self.primary_key = "id"
  belongs_to :case, class_name: "Case", foreign_key: "case_id", primary_key: "id", optional: false
  belongs_to :created_by, class_name: "Account", foreign_key: "created_by", primary_key: "id", optional: false
end
