module Journeys
  # FR003 / FR007: registration is limited to the nine Bay Area counties.
  # Directory membership validates the entered location, not residence or identity.
  class RegistrationLocation
    def self.validate!(value)
      raise Error, I18n.t("registration.outside_service_area") unless eligible?(value)
    end

    def self.eligible?(value)
      text = value.to_s.strip.downcase.gsub(/\s+/, " ")
      rows = JSON.parse(Rails.root.join("config/data/bay_area_locations.json").read).fetch("locations")
      if text.match?(/\A\d{5}(?:-\d{4})?\z/)
        return rows.any? { |row| row["zip_code"] == text[0, 5] }
      end
      # Accept the autocomplete value and typed town/ZIP combinations, but
      # require both components to match the same directory entry.
      match = text.match(/\A(.+?)[ ,·]+(\d{5})(?:-\d{4})?\z/)
      town = (match ? match[1] : text).sub(/,? (?:ca|california)\z/, "").strip
      rows.any? do |row|
        row.fetch("town").downcase == town && (!match || row["zip_code"] == match[2])
      end
    end
  end
end
