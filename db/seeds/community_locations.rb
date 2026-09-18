# Approved community locations: Monday-Friday, 9 AM-3 PM Pacific.
# Run with: bin/rails runner db/seeds/community_locations.rb
days = [1, 2, 3, 4, 5]
names = ["San Jose Senior Center", "Jain Center of Northen California", "iMotion - Freemont", "Pleasonton Senior Center", "Dublin Senior Center"]
Workflow.run do
  names.each do |name|
    matches = Location.where(name: name).to_a
    raise "Multiple locations named #{name}; resolve duplicates before continuing." if matches.length > 1
    location = matches.first || Location.create!(name: name, timezone: "America/Los_Angeles")
    days.each do |day|
      hours = LocationHour.find_or_initialize_by(location_id: location.id, weekday: day, opens_local: "09:00")
      hours.update!(closes_local: "15:00")
    end
  end
end
puts "Saved five locations with 9 AM–3 PM Pacific hours on weekdays #{days.sort.join(', ')}."
