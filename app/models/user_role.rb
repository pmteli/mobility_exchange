class UserRole < MobilityRecord
  self.table_name = "mobility_exchange.user_roles"
  self.primary_key = ["user_id", "role_id"]
end
