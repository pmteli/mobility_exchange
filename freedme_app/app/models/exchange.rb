# PostgreSQL v0.2 owns constraints, lifecycle triggers and UUID defaults.
class Exchange < ApplicationRecord
  self.table_name = "freedme.exchanges"
  self.primary_key = "id"
  belongs_to :requester, class_name: "Account", foreign_key: "requester_id", primary_key: "id", optional: false
  belongs_to :donor, class_name: "Account", foreign_key: :donor_id
  belongs_to :listing, foreign_key: [ :listing_id, :donor_id ], primary_key: [ :id, :donor_id ]
  belongs_to :revision, class_name: "ListingRevision", foreign_key: [ :listing_id, :revision_id ], primary_key: [ :listing_id, :id ]
  belongs_to :representation, foreign_key: [ :representation_id, :requester_id ], primary_key: [ :id, :representative_id ], optional: true
end
