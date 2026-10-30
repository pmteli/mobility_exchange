module ApplicationHelper
  # FR003/FR004/FR007: approximate location suggestions; no street address required.
  def east_bay_location_options
    @east_bay_location_options ||= JSON.parse(Rails.root.join("config/data/east_bay_locations.json").read).fetch("locations")
  end
end
