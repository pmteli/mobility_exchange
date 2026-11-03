module JourneysHelper
  def donor_request_summary(exchange)
    name = "Recipient name unavailable"
    if exchange.donor_id == current_account.id && %w[pending offered reserved loaned].include?(exchange.state)
      sql = ApplicationRecord.sanitize_sql_array([
        "SELECT field_name, encode(value_ciphertext, 'base64') AS ciphertext FROM freedme.read_donor_identity(?, ?)",
        current_account.id, exchange.id
      ])
      fields = ApplicationRecord.connection.select_all(sql).to_a.to_h do |row|
        [row["field_name"], Journeys::Support.decrypt(Base64.decode64(row["ciphertext"]))]
      end
      verified_name = [fields["first_name"], fields["last_name"]].compact.join(" ").strip
      name = verified_name if verified_name.present?
    end
    requested_at = exchange.requested_at.in_time_zone
    "Requested by #{name} on #{requested_at.strftime('%b %-d, %Y')} at #{requested_at.strftime('%-I:%M %p %Z')}"
  end

  def recipient_request_summary(exchange)
    requested_at = exchange.requested_at.in_time_zone
    "You requested this equipment from #{exchange.donor.display_name} on #{requested_at.strftime('%b %-d, %Y')} at #{requested_at.strftime('%-I:%M %p %Z')}"
  end

  def revision_for(listing)
    ListingRevision.find(listing.current_revision_id)
  end
  def local_text(ciphertext)
    Journeys::Support.decrypt(ciphertext)
  end
end
