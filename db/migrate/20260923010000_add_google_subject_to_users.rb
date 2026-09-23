class AddGoogleSubjectToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column "mobility_exchange.users", :google_subject, :string, limit: 255
    add_index "mobility_exchange.users", :google_subject, unique: true
  end
end
