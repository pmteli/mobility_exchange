class IdentityDocumentUpload < ApplicationRecord
  self.table_name = 'freedme.identity_document_uploads'
  belongs_to :account
  belongs_to :listing
  def name_corrected?
    fields = extracted_fields
    original = fields['_extracted_name']
    original.present? && %w[first_name last_name].any? { |key| original[key].to_s != fields[key].to_s }
  end
  def extracted_fields
    fields_ciphertext ? JSON.parse(IdentityDocuments::Vault.decrypt(fields_ciphertext)) : {}
  end
end
