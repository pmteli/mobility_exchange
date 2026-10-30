# PostgreSQL v0.2 owns constraints, lifecycle triggers and UUID defaults.
class SensitiveAccessEvent < ApplicationRecord
  self.table_name = "freedme.sensitive_access_events"
  self.primary_key = "id"
  belongs_to :actor, class_name: "Account", foreign_key: "actor_id", primary_key: "id", optional: false
  belongs_to :grant, class_name: "DisclosureGrant", foreign_key: "grant_id", primary_key: "id", optional: true
  belongs_to :evidence, class_name: "IdentityEvidence", foreign_key: "evidence_id", primary_key: "id", optional: true
end
