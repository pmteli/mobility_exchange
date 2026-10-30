# PostgreSQL v0.2 owns constraints, lifecycle triggers and UUID defaults.
class BorrowerField < ApplicationRecord
  self.table_name = "freedme.borrower_fields"
  self.primary_key = [ "evidence_id", "field_name" ]
  belongs_to :evidence, class_name: "IdentityEvidence", foreign_key: "evidence_id", primary_key: "id", optional: false
end
