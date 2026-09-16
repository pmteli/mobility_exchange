Workflow.run do
  actor = User.find_or_create_by!(id: "demo-system") do |user|
    user.auth_subject = "demo:no-login"
    user.email = "demo-system@example.test"
    user.first_name = "Sample"
    user.last_name = "Data"
    user.account_status = "active"
    user.email_verified_at = Time.current
  end
  location = Location.find_or_create_by!(id: "demo-center") do |record|
    record.name = "Sample Community Center"
    record.timezone = "America/Los_Angeles"
    record.pickup_enabled = true
    record.dropoff_enabled = true
    record.instructions = "Sample location for development only."
  end
  [["manual-wheelchair", "wheelchairs", "Manual wheelchair"], ["rollator", "walkers", "Four-wheel rollator"], ["shower-chair", "bath", "Shower chair"]].each do |id, category, name|
    type = EquipmentType.find_or_create_by!(id: "demo-#{id}") { |record| record.category_id = category; record.name = name }
    next if Equipment.exists?(id: "demo-#{id}")
    equipment = Equipment.create!(id: "demo-#{id}", inventory_number: "SAMPLE-#{id.upcase}", type_id: type.id, name: name, description: "Sample equipment for exploring the application. Replace with verified details before offering real equipment.", condition: "good", acquisition_kind: "legacy", location_id: location.id, received_at: Time.current, created_by: actor.id, updated_by: actor.id)
    %w[awaiting_inspection inspected awaiting_sanitization sanitized cataloged available].each do |status|
      if status == "inspected" || status == "sanitized"
        ProcessingEvent.create!(equipment_id: equipment.id, kind: status == "inspected" ? "inspection" : "sanitization", outcome: status == "inspected" ? "passed" : "completed", performed_by: actor.id, performed_at: Time.current, notes: "SAMPLE processing evidence; not a real inspection.")
      end
      equipment.update!(status_code: status)
    end
  end
  {"about" => ["About Mobility Exchange", "We connect people with mobility equipment and give donated items another useful chapter.

This is sample website content. Replace it with your organization's approved information."], "faq" => ["Frequently asked questions", "How do I request equipment?
Browse available items, create an account, and submit a request. The team reviews each request before reserving equipment.

How do I donate?
Submit the donation form, sign the donor certification, and wait for review before arranging drop-off."], "contact" => ["Contact the team", "Add your organization's approved contact details, hours, and locations here."]}.each do |slug, (title, body)|
    ContentPage.find_or_create_by!(slug: slug) { |page| page.title = title; page.body_markdown = body; page.published_at = Time.current; page.updated_by = actor.id }
  end
end
puts "Three sample items and sample pages created. No login passwords or legal documents were seeded."
