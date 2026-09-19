class AllowPreservedRecordsWithoutUserAttribution < ActiveRecord::Migration[8.1]
  def change
    {
      appointment_slots: [:created_by],
      content_pages: [:updated_by],
      equipment: [:created_by, :updated_by],
      legal_document_versions: [:published_by],
      organization_settings: [:updated_by],
      volunteer_shifts: [:created_by]
    }.each do |table, columns|
      columns.each { |column| change_column_null "mobility_exchange.#{table}", column, true }
    end
  end
end
