module ApplicationHelper
  def navigation_section
    path = request.path
    return :donate if path.match?(%r{\A/(donate|listings)(/|$)})
    return :equipment if path.match?(%r{\A/(equipment|identity-documents)(/|$)})
    return :activity if path.match?(%r{\A/(activity|transactions|donor|recipient|moderator)(/|$)})
    return :how if path == "/how-it-works"
    return :resources if path == "/resources"
    return :signin if path.match?(%r{\A/(sign-in|register)(/|$)})
  end

  def main_navigation_link(label, path, section)
    link_to label, path, aria: { current: navigation_section == section ? "page" : nil }
  end

  # FR003/FR004/FR007: approximate location suggestions; no street address required.
  def bay_area_location_options
    @bay_area_location_options ||= JSON.parse(Rails.root.join("config/data/bay_area_locations.json").read).fetch("locations")
  end
end
