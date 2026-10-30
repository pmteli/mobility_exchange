# PostgreSQL v0.2 owns constraints, lifecycle triggers and UUID defaults.
class DeletionJob < ApplicationRecord
  self.table_name = "freedme.deletion_jobs"
  self.primary_key = "id"
  belongs_to :rule, class_name: "RetentionRule", foreign_key: "rule_id", primary_key: "id", optional: false
end
