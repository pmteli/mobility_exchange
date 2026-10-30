# PostgreSQL v0.2 owns constraints, lifecycle triggers and UUID defaults.
class IdentityEvidence < ApplicationRecord
  self.table_name = "freedme.identity_evidence"
  self.primary_key = "id"
  belongs_to :submitted_by_account, class_name: "Account", foreign_key: "submitted_by", primary_key: "id", optional: false
  belongs_to :representation, class_name: "Representation", foreign_key: "representation_id", primary_key: "id", optional: true
  belongs_to :reviewer, class_name: "Account", foreign_key: "reviewer_id", primary_key: "id", optional: true
  belongs_to :policy, class_name: "PolicyVersion", foreign_key: "policy_id", primary_key: "id", optional: false
  belongs_to :replaces_evidence, class_name: "IdentityEvidence", foreign_key: "replaces_evidence_id", primary_key: "id", optional: true
end
