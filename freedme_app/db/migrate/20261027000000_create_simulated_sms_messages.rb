class CreateSimulatedSmsMessages < ActiveRecord::Migration[8.1]
  def change
    create_table "freedme.simulated_sms_messages", id: :uuid, default: -> { "uuidv7()" } do |t|
      t.string :recipient, null: false
      t.string :template_code, null: false
      t.text :body, null: false
      t.string :idempotency_key
      t.timestamps
    end
    add_index "freedme.simulated_sms_messages", :idempotency_key, unique: true
  end
end
