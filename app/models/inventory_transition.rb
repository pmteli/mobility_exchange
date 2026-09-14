class InventoryTransition < MobilityRecord
  self.table_name = "mobility_exchange.inventory_transitions"
  self.primary_key = ["from_status", "to_status"]
end
