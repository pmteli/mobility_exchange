# PostgreSQL v0.2 owns constraints, lifecycle triggers and UUID defaults.
class AccountRole < ApplicationRecord
  self.table_name = "freedme.account_roles"
  self.primary_key = [ "account_id", "role" ]
  belongs_to :account, class_name: "Account", foreign_key: "account_id", primary_key: "id", optional: false
  belongs_to :granted_by_account, class_name: "Account", foreign_key: "granted_by", primary_key: "id", optional: true
end
