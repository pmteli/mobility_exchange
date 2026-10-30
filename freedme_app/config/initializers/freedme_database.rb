# Preserve triggers, functions and all schemas in this dedicated application database.
Rails.application.config.active_record.schema_format = :sql
# pg_dump without --schema=public preserves the built-in public schema correctly.
Rails.application.config.active_record.dump_schemas = :all

# Rails passes --no-privileges to pg_dump. Reapply the v0.2 public-access
# restrictions in SQL dumps as well as migrations; otherwise restored functions
# would regain PostgreSQL's default PUBLIC EXECUTE permission.
require "active_record/tasks/postgresql_database_tasks"
module FreedmeStructurePrivileges
  def structure_dump(filename, extra_flags)
    super
    File.open(filename, "a") do |file|
      file.write(<<~SQL)
        REVOKE ALL ON ALL TABLES IN SCHEMA freedme FROM PUBLIC;
        REVOKE ALL ON ALL FUNCTIONS IN SCHEMA freedme FROM PUBLIC;
        ALTER DEFAULT PRIVILEGES IN SCHEMA freedme REVOKE ALL ON TABLES FROM PUBLIC;
        ALTER DEFAULT PRIVILEGES IN SCHEMA freedme REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
      SQL
    end
  end
end
ActiveRecord::Tasks::PostgreSQLDatabaseTasks.prepend(FreedmeStructurePrivileges)
