class RolePermission < MobilityRecord
  self.table_name = "mobility_exchange.role_permissions"
  self.primary_key = ["role_id", "permission_id"]
end
