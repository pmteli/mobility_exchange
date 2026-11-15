class PrivacyDeletionRequest < ApplicationRecord
  self.table_name = 'freedme.privacy_deletion_requests'
  belongs_to :account
end
