class AddUserProfileFields < ActiveRecord::Migration[8.1]
  def change
    change_table "mobility_exchange.users" do |t|
      t.string :address_line1, limit: 200
      t.string :address_line2, limit: 200
      t.string :city, limit: 100
      t.string :region, limit: 100
      t.string :postal_code, limit: 20
      t.string :pending_email, limit: 254
      t.string :pending_email_nonce, limit: 64
    end
  end
end
