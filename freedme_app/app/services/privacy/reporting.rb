module Privacy
  # Explicit allowlist: no names, geography, exact dates, messages, photos or free text.
  # Internal source links are private operational metadata, never exported.
  class Reporting
    def self.capture!(exchange)
      return unless exchange.retention_ended_at
      revision = ListingRevision.find(exchange.revision_id)
      ReportingArchive.create_or_find_by!(exchange_id: exchange.id) do |row|
        row.assign_attributes(attributes(revision).merge(listing_id: exchange.listing_id,
          outcome: exchange.retention_end_reason))
      end
    end

    def self.attributes(revision)
      category = Category.find(EquipmentConfiguration.find(revision.configuration_id).category_id)
      {category_code: category.code, offer_kind: revision.offer_kind}
    end

    def self.run!
      Exchange.where.not(retention_ended_at: nil).find_each { |exchange| capture!(exchange) }
      Listing.where(status: 'withdrawn').find_each do |listing|
        revision = ListingRevision.find(listing.current_revision_id)
        ReportingArchive.create_or_find_by!(listing_id: listing.id, exchange_id: nil) do |row|
          row.assign_attributes(attributes(revision).merge(outcome: 'withdrawn'))
        end
      end
    end

    def self.summary
      ReportingArchive.group(:category_code, :offer_kind, :outcome).count.map do |(category, kind, outcome), count|
        {category: category, offer_kind: kind, outcome: outcome, count: count}
      end
    end
  end
end
