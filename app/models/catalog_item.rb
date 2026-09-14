# A deliberately restricted database view: public controllers never query private fields.
class CatalogItem < ApplicationRecord
  self.table_name = "mobility_exchange.public_available_equipment"
  self.primary_key = "id"
  def readonly?
    true
  end
end
