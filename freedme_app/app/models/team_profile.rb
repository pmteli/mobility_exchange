# PostgreSQL v0.2 owns constraints, lifecycle triggers and UUID defaults.
class TeamProfile < ApplicationRecord
  self.table_name = "freedme.team_profiles"
  self.primary_key = "id"
end
