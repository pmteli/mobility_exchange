# PostgreSQL v0.2 owns constraints, lifecycle triggers and UUID defaults.
class MessageAttempt < ApplicationRecord
  self.table_name = "freedme.message_attempts"
  self.primary_key = "id"
  belongs_to :job, class_name: "MessageJob", foreign_key: "job_id", primary_key: "id", optional: false
end
