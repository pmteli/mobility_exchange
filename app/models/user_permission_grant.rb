class UserPermissionGrant < MobilityRecord
  self.table_name = "mobility_exchange.user_permission_grants"
  self.primary_key = ["user_id", "permission_id"]
end
