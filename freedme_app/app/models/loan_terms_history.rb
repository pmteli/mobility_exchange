# PostgreSQL v0.2 owns constraints, lifecycle triggers and UUID defaults.
class LoanTermsHistory < ApplicationRecord
  self.table_name = "freedme.loan_terms_history"
  self.primary_key = "id"
  belongs_to :exchange, class_name: "Exchange", foreign_key: "exchange_id", primary_key: "id", optional: false
  belongs_to :reported_by, class_name: "Account", foreign_key: "reported_by", primary_key: "id", optional: false
  belongs_to :timing_policy, class_name: "PolicyVersion", foreign_key: "timing_policy_id", primary_key: "id", optional: false
end
