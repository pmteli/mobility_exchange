# Bound SQL values; no user-supplied sort or column names.
class EquipmentCatalog
  PAGE_SIZE = 24

  def self.call(query: nil, category_id: nil, offer_kind: nil, page: 1)
    scope = AvailableListingCard.order(:title, :id)
    if query.present?
      term = "%#{AvailableListingCard.sanitize_sql_like(query.to_s.first(100))}%"
      scope = scope.where("title ILIKE :term OR description ILIKE :term OR public_locality ILIKE :term", term: term)
    end
    scope = scope.where(category_id: category_id) if category_id.to_s.match?(/\A[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\z/i)
    scope = scope.where(offer_kind: offer_kind) if %w[gift loan].include?(offer_kind)
    scope.limit(PAGE_SIZE).offset(([ page.to_i, 1 ].max.clamp(1, 1000) - 1) * PAGE_SIZE)
  end
end
