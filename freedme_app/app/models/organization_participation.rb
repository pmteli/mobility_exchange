# PostgreSQL v0.2 owns constraints, lifecycle triggers and UUID defaults.
class OrganizationParticipation < ApplicationRecord
  self.table_name = "freedme.organization_participation"
  self.primary_key = "id"
end
