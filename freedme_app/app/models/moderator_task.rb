# PostgreSQL v0.2 owns constraints, lifecycle triggers and UUID defaults.
class ModeratorTask < ApplicationRecord
  self.table_name = "freedme.moderator_tasks"
  self.primary_key = "id"
  belongs_to :exchange, class_name: "Exchange", foreign_key: "exchange_id", primary_key: "id", optional: false
  belongs_to :assigned_to_account, class_name: "Account", foreign_key: "assigned_to", primary_key: "id", optional: true
end
