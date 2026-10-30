# PostgreSQL v0.2 owns constraints, lifecycle triggers and UUID defaults.
class CaseAction < ApplicationRecord
  self.table_name = "freedme.case_actions"
  self.primary_key = "id"
  belongs_to :case, class_name: "Case", foreign_key: "case_id", primary_key: "id", optional: false
  belongs_to :actor, class_name: "Account", foreign_key: "actor_id", primary_key: "id", optional: false
end
