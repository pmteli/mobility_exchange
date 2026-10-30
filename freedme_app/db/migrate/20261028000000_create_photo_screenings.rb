class CreatePhotoScreenings < ActiveRecord::Migration[8.1]
  def change
    create_table "freedme.photo_screenings", id: :uuid, default: -> { "uuidv7()" } do |t|
      t.uuid :account_id, null: false
      t.string :image_digest, null: false
      t.string :policy_key, null: false
      t.string :state, null: false, default: "unavailable"
      t.jsonb :labels, null: false, default: []
      t.string :model_version
      t.integer :attempts, null: false, default: 0
      t.datetime :last_attempt_at
      t.datetime :checked_at
      t.timestamps
    end
    add_foreign_key "freedme.photo_screenings", "freedme.accounts", column: :account_id
    add_index "freedme.photo_screenings", [:account_id, :image_digest, :policy_key], unique: true, name: "photo_screenings_content_policy"
    add_check_constraint "freedme.photo_screenings", "state IN ('accepted','needs_review','rejected','unavailable')", name: "photo_screening_state"
  end
end
