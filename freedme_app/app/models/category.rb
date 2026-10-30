# PostgreSQL v0.2 owns constraints, lifecycle triggers and UUID defaults.
class Category < ApplicationRecord
  self.table_name = "freedme.categories"
  self.primary_key = "id"
end
