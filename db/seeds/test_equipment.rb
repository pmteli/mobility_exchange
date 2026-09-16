# Fictional equipment for the designated test site only; safe to run repeatedly.
unless Rails.env.test? || Rails.env.development? ||
       (ENV["DEPLOYMENT_STAGE"] == "test" && ENV["APP_HOST"] == "test.mobilityexchange.org")
  raise "Sample equipment is restricted to development and the designated AWS test site."
end
items = {
  "wheelchairs" => ["Standard manual wheelchair", "Lightweight manual wheelchair", "Folding travel wheelchair", "Transport wheelchair", "Wide-seat manual wheelchair", "Reclining manual wheelchair"],
  "walkers" => ["Standard folding walker", "Two-wheel walker", "Four-wheel rollator", "Compact rollator", "Wide-seat rollator", "Height-adjustable walker", "Travel folding walker"],
  "bath" => ["Shower chair with backrest", "Compact shower chair", "Height-adjustable shower chair", "Shower chair with armrests", "Wide-seat shower chair"],
  "walking_aids" => ["Single-point cane", "Quad-base cane", "Folding travel cane", "Offset-handle cane", "Underarm crutches", "Forearm crutches", "Adjustable adult crutches"]
}
Workflow.run do
  actor = User.find_or_create_by!(id: "sample-equipment-system") do |u|
    u.auth_subject = "seed:equipment:no-login"
    u.email = "equipment-system@example.test"
    u.first_name = "Sample"
    u.last_name = "Equipment"
    u.account_status = "active"
    u.email_verified_at = Time.current
  end
  location = Location.find_or_create_by!(id: "sample-equipment-center") do |l|
    l.name = "Sample Bay Area Center"
    l.timezone = "America/Los_Angeles"
    l.pickup_enabled = true
    l.dropoff_enabled = true
    l.instructions = "Fictional test location; no actual pickup is available."
  end
  items.each do |category, names|
    names.each do |name|
      id = "sample-equipment-#{name.parameterize}"
      type = EquipmentType.find_or_create_by!(id: id) { |t| t.category_id = category; t.name = name }
      next if Equipment.exists?(id: id)
      equipment = Equipment.create!(id: id, inventory_number: "TEST-#{category.upcase}-#{names.index(name) + 1}",
        type_id: type.id, name: "#{name} (Sample)", condition: "good", acquisition_kind: "legacy",
        description: "Fictional #{name.downcase} for testing Mobility Exchange. The picture is a category illustration; it does not show a real donated item. No actual equipment is offered.",
        location_id: location.id, received_at: Time.current, created_by: actor.id, updated_by: actor.id)
      %w[awaiting_inspection inspected awaiting_sanitization sanitized cataloged available].each do |status|
        if %w[inspected sanitized].include?(status)
          ProcessingEvent.create!(equipment_id: id, kind: status == "inspected" ? "inspection" : "sanitization",
            outcome: status == "inspected" ? "passed" : "completed", performed_by: actor.id,
            performed_at: Time.current, notes: "Fictional test evidence only; no real inspection or sanitization performed.")
        end
        equipment.update!(status_code: status)
      end
    end
  end
end
puts "25 sample equipment items ready across 4 categories, with category illustrations. Existing items preserved."
