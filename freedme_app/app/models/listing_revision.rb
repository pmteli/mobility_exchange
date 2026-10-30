# PostgreSQL v0.2 owns constraints, lifecycle triggers and UUID defaults.
class ListingRevision < ApplicationRecord
  self.table_name = "freedme.listing_revisions"
  self.primary_key = "id"
  belongs_to :listing, class_name: "Listing", foreign_key: "listing_id", primary_key: "id", optional: false
  belongs_to :configuration, class_name: "EquipmentConfiguration", foreign_key: "configuration_id", primary_key: "id", optional: false
  belongs_to :service_area, class_name: "ServiceArea", foreign_key: "service_area_id", primary_key: "id", optional: false
end
