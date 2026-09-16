class AllowRecipientCommunityRole < ActiveRecord::Migration[8.1]
  def up
    remove_check_constraint "mobility_exchange.users", name: "users_community_roles_allowed"
    add_check_constraint "mobility_exchange.users", "community_roles <@ ARRAY['volunteer', 'donor', 'recipient']::text[]", name: "users_community_roles_allowed"
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Recipient selections must be handled before restoring the previous constraint."
  end
end
