class CreateListingReviewAlerts < ActiveRecord::Migration[8.1]
  def change
    create_table "freedme.listing_review_alerts" do |t|
      t.uuid :account_id, null: false
      t.uuid :revision_id, null: false
      t.string :email_state, null: false, default: "queued"
      t.string :sms_state, null: false, default: "queued"
      t.timestamps
    end
    add_index "freedme.listing_review_alerts", [:account_id, :revision_id], unique: true
    add_foreign_key "freedme.listing_review_alerts", "freedme.accounts", column: :account_id, on_delete: :cascade
    add_foreign_key "freedme.listing_review_alerts", "freedme.listing_revisions", column: :revision_id, on_delete: :cascade
  end
end
