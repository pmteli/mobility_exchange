# PostgreSQL v0.2 owns constraints, lifecycle triggers and UUID defaults.
class AccountContact < ApplicationRecord
  self.table_name = "freedme.account_contacts"
  self.primary_key = "id"
  belongs_to :account, class_name: "Account", foreign_key: "account_id", primary_key: "id", optional: false
end
