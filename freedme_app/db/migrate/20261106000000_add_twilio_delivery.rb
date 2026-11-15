class AddTwilioDelivery < ActiveRecord::Migration[8.1]
  def change
    add_column "freedme.auth_challenges", :provider, :string, null: false, default: "simulated"
    add_column "freedme.auth_challenges", :provider_sid, :string
    create_table "freedme.sms_deliveries", id: :uuid, default: -> { "uuidv7()" } do |t|
      t.text :recipient_ciphertext, null: false
      t.binary :recipient_hmac, null: false
      t.text :body_ciphertext, null: false
      t.string :template_code, null: false
      t.string :idempotency_key, null: false
      t.string :state, null: false, default: "queued"
      t.string :provider_sid
      t.string :delivery_status
      t.string :error_code
      t.timestamps
    end
    add_index "freedme.sms_deliveries", :idempotency_key, unique: true
    add_index "freedme.sms_deliveries", [:state, :created_at]
    add_check_constraint "freedme.sms_deliveries", "state IN ('queued', 'sending', 'accepted', 'failed', 'suppressed')", name: "sms_delivery_state"
  end
end
