class CreateIdentityDocumentUploads < ActiveRecord::Migration[8.1]
  def change
    create_table 'freedme.identity_document_uploads', id: :uuid, default: -> { 'uuidv7()' } do |t|
      t.uuid :account_id, null: false
      t.uuid :listing_id, null: false
      t.uuid :revision_id, null: false
      t.uuid :exchange_id
      t.string :document_kind, null: false
      t.string :state, null: false, default: 'processing'
      t.binary :image_ciphertext
      t.binary :fields_ciphertext
      t.datetime :purge_due_at, null: false
      t.datetime :image_deleted_at
      t.datetime :confirmed_at
      t.timestamps
    end
    add_foreign_key 'freedme.identity_document_uploads', 'freedme.accounts', column: :account_id
    add_foreign_key 'freedme.identity_document_uploads', 'freedme.listings', column: :listing_id
    add_foreign_key 'freedme.identity_document_uploads', 'freedme.listing_revisions', column: :revision_id
    add_foreign_key 'freedme.identity_document_uploads', 'freedme.exchanges', column: :exchange_id
    add_index 'freedme.identity_document_uploads', [:account_id, :created_at]
    add_index 'freedme.identity_document_uploads', :purge_due_at
    add_check_constraint 'freedme.identity_document_uploads', "state IN ('processing','extracted','failed','confirmed')", name: 'identity_upload_state'
    add_check_constraint 'freedme.identity_document_uploads', "document_kind IN ('utility_bill','government_id')", name: 'identity_upload_kind'
  end
end
