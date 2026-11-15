require "test_helper"

class RegistrationLocationTest < ActiveSupport::TestCase
  test "accepts directory towns ZIPs and autocomplete options across all counties" do
    rows = JSON.parse(Rails.root.join("config/data/bay_area_locations.json").read).fetch("locations")
    rows.each do |row|
      assert Journeys::RegistrationLocation.eligible?(row.fetch("town"))
      next unless row["zip_code"]
      assert Journeys::RegistrationLocation.eligible?(row["zip_code"])
      assert Journeys::RegistrationLocation.eligible?("#{row['town']} · #{row['zip_code']}")
    end
    ["  fReMoNt  ", "94536-1234", "Fremont, CA 94536", "Fremont, California"].each do |value|
      assert Journeys::RegistrationLocation.eligible?(value), value
    end
  end

  test "rejects unknown and contradictory locations" do
    [nil, "", "90001", "Los Angeles", "Fremont NY", "Fremont 90001", "Los Angeles 94536", "945360", "outside 94536"].each do |value|
      refute Journeys::RegistrationLocation.eligible?(value), value.inspect
    end
  end
end
