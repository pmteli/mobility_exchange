# Approved dated shifts. Run: bin/rails runner db/seeds/community_shifts.rb
names = ["San Jose Senior Center", "Jain Center of Northen California", "iMotion - Freemont", "Pleasonton Senior Center", "Dublin Senior Center"]
dates = (Date.new(2026, 9, 21)..Date.new(2026, 10, 21)).reject { |date| date.saturday? || date.sunday? }
Workflow.run do
  actor = User.joins(:user_roles).where(user_roles: {role_id: "admin"}, account_status: "active").first!
  Workflow.authorize!(actor, "shifts.manage")
  names.each do |name|
    locations = Location.where(name: name, status: "active").to_a
    raise "Expected exactly one active location: #{name}" unless locations.one?
    location = locations.first
    zone = ActiveSupport::TimeZone[location.timezone]
    dates.each do |date|
      starts_at = zone.local(date.year, date.month, date.day, 10)
      ends_at = zone.local(date.year, date.month, date.day, 14)
      matches = VolunteerShift.where(location_id: location.id, starts_at: starts_at).to_a
      raise "Multiple shifts at #{name} on #{date}" if matches.length > 1
      if (existing = matches.first)
        raise "Existing shift differs at #{name} on #{date}; review before replacing" unless existing.ends_at == ends_at && existing.capacity == 3 && existing.cancelled_at.nil?
        next
      end
      shift = VolunteerShift.create!(location_id: location.id, activity: "Community volunteering", starts_at: starts_at, ends_at: ends_at, capacity: 3, created_by: actor.id)
      Audit.record!(actor, "shifts.created", shift)
    end
  end
end
puts "Verified #{dates.length * names.length} weekday shifts, 10 AM–2 PM Pacific, capacity 3."
