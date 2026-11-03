require "test_helper"

class BayAreaLocationsTest < ActionView::TestCase
  include ApplicationHelper

  test "directory covers all nine counties with searchable ZIP and town values" do
    rows = bay_area_location_options
    assert_equal ["Alameda", "Contra Costa", "Marin", "Napa", "San Francisco", "San Mateo", "Santa Clara", "Solano", "Sonoma"], rows.map { |row| row.fetch("county") }.uniq.sort
    {"San Francisco" => "94103", "San Jose" => "95112", "San Mateo" => "94401", "San Rafael" => "94901", "Napa" => "94558", "Fairfield" => "94533", "Santa Rosa" => "95401", "Fremont" => "94536", "Concord" => "94520"}.each do |town, zip|
      assert rows.any? { |row| row["town"] == town && row["zip_code"] == zip }, "Missing #{town} #{zip}"
    end
    assert rows.all? { |row| row["zip_code"].nil? || row["zip_code"].match?(/\A\d{5}\z/) }
    assert_equal rows.uniq, rows
  end
end
