class ActiveLegalDocument < MobilityRecord
  self.table_name = "mobility_exchange.active_legal_documents"
  self.primary_key = "kind"
end
