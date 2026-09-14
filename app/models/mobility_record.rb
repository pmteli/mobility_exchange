class MobilityRecord < ApplicationRecord
  self.abstract_class = true
  before_create :assign_opaque_id
  private
  def assign_opaque_id
    self.id ||= SecureRandom.uuid if self.class.primary_key == "id" && self.class.columns_hash["id"].type == :text
  end
end
