# PostgreSQL v0.2 owns constraints, lifecycle triggers and UUID defaults.
class DisclosureGrant < ApplicationRecord
  self.table_name = "freedme.disclosure_grants"
  self.primary_key = "id"
  belongs_to :exchange, class_name: "Exchange", foreign_key: "exchange_id", primary_key: "id", optional: false
  belongs_to :evidence, class_name: "IdentityEvidence", foreign_key: "evidence_id", primary_key: "id", optional: false
  belongs_to :consented_by_account, class_name: "Account", foreign_key: "consented_by", primary_key: "id", optional: false
  belongs_to :donor, class_name: "Account", foreign_key: "donor_id", primary_key: "id", optional: false
  belongs_to :consent_policy, class_name: "PolicyVersion", foreign_key: "consent_policy_id", primary_key: "id", optional: false
end
