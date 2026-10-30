# PostgreSQL v0.2 owns constraints, lifecycle triggers and UUID defaults.
class NotificationTemplate < ApplicationRecord
  self.table_name = "freedme.notification_templates"
  self.primary_key = [ "code", "version" ]
end
