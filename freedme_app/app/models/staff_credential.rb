# PostgreSQL v0.2 owns constraints, lifecycle triggers and UUID defaults.
class StaffCredential < ApplicationRecord
  has_secure_password
  validates :password, length: {minimum: 8}, allow_nil: true
  validates :username, presence: true, uniqueness: true
  self.table_name = "freedme.staff_credentials"
  self.primary_key = "account_id"
  belongs_to :account, class_name: "Account", foreign_key: "account_id", primary_key: "id", optional: false
  belongs_to :email_contact, class_name: "AccountContact", foreign_key: "email_contact_id", primary_key: "id", optional: false
end
