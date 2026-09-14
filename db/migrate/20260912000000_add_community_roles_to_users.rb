class AddCommunityRolesToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column "mobility_exchange.users", :community_roles, :text, array: true, default: [], null: false
    add_check_constraint "mobility_exchange.users", "community_roles <@ ARRAY['volunteer', 'donor']::text[]", name: "users_community_roles_allowed"
  end
end
