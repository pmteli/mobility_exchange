class SeedTestEquipment < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    # Live production must never receive fictional inventory.
    return unless Rails.env.test? || Rails.env.development? ||
      (ENV["DEPLOYMENT_STAGE"] == "test" && ENV["APP_HOST"] == "test.mobilityexchange.org")
    load Rails.root.join("db/seeds/test_equipment.rb")
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Sample equipment may be linked to test requests; remove it explicitly after reviewing those records."
  end
end
