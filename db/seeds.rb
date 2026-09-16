load Rails.root.join("db/seeds/mobility_exchange.rb")
puts "Reference roles, permissions and inventory states are ready. Run bin/rails mobility:demo for optional sample data."
load Rails.root.join("db/seeds/test_users.rb") if ENV["SEED_TEST_USERS"] == "1"
load Rails.root.join("db/seeds/test_equipment.rb") if ENV["SEED_TEST_EQUIPMENT"] == "1"
