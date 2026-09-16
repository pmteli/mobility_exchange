class SchemaVersion < MobilityRecord
  self.table_name = "mobility_exchange.schema_versions"
  self.primary_key = "version"
end
