class CreateMoneyDonations < ActiveRecord::Migration[8.1]
  def change
    create_table "mobility_exchange.money_donations", id: :text do |t|
      t.text :user_id, null: false
      t.text :request_key, null: false
      t.text :email, null: false
      t.integer :amount_cents, null: false
      t.text :currency, null: false, default: "usd"
      t.text :status, null: false, default: "pending"
      t.text :stripe_session_id
      t.text :stripe_payment_intent_id
      t.datetime :paid_at
      t.timestamps
    end
    add_foreign_key "mobility_exchange.money_donations", "mobility_exchange.users", column: :user_id
    add_index "mobility_exchange.money_donations", [:user_id, :request_key], unique: true, name: "money_donations_request_unique"
    add_index "mobility_exchange.money_donations", :stripe_session_id, unique: true
    add_index "mobility_exchange.money_donations", :stripe_payment_intent_id, unique: true
    add_check_constraint "mobility_exchange.money_donations", "amount_cents BETWEEN 100 AND 1000000 AND currency = 'usd'", name: "money_donation_amount"
    add_check_constraint "mobility_exchange.money_donations", "status IN ('pending', 'paid', 'expired')", name: "money_donation_status"
    add_check_constraint "mobility_exchange.money_donations", "(status = 'paid') = (paid_at IS NOT NULL AND stripe_payment_intent_id IS NOT NULL)", name: "money_donation_paid_evidence"
  end
end
