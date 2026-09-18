module DesignHelper
  def design_icon(name)
    render "design/icons/#{name}"
  end
  EQUIPMENT_PHOTO_CREDITS = JSON.parse(File.read(Rails.root.join("public/design/equipment-photos/credits.json"))).freeze
  def equipment_photo_credits
    EQUIPMENT_PHOTO_CREDITS
  end
  def equipment_photo(category, type = "")
    text = (type.present? ? type : category).to_s.downcase
    kind = if text.include?("wheelchair") then "wheelchair"
      elsif text.include?("bath") || text.include?("shower") then "shower-chair"
      elsif text.include?("forearm") && text.include?("crutch") then "forearm-crutches"
      elsif text.include?("crutch") then "crutches"
      elsif text.include?("cane") then "cane"
      elsif text.include?("rollator") then "rollator"
      elsif text.include?("walker") then "walker"
      end
    photo = equipment_photo_credits[kind]
    return tag.span("Photo not available", class: "equipment-photo-placeholder") unless photo
    image_tag "/design/equipment-photos/#{photo.fetch('file')}",
      alt: "Representative photo: #{photo.fetch('label')}. Not the specific donated item.",
      class: "product-illustration equipment-photo", loading: "lazy", decoding: "async"
  end
  def operations_links
    [
      ["Overview", staff_root_path, "grid", nil],
      ["Equipment inventory", staff_equipment_index_path, "box", "inventory.read"],
      ["Donation intake", staff_donations_path, "heart", "intake.review"],
      ["Requests & pickup", staff_requests_path, "file", "distribution.manage"],
      ["Appointments", staff_slots_path, "calendar", "distribution.manage"],
      ["Volunteers", staff_volunteers_path, "people", "users.manage"],
      ["Volunteer shifts", staff_shifts_path, "clock", "shifts.manage"],
      ["Website content", staff_pages_path, "file", "content.manage"],
      ["Reports", staff_reports_path, "chart", "reports.read"]
    ].select { |_, _, _, permission| permission.nil? || allowed?(permission) }
  end
  def current_operations_page
    operations_links.reverse.find { |_, path, _, _| request.path == path || request.path.start_with?("#{path}/") }&.first || "Overview"
  end
  def initials(user)
    [user.first_name, user.last_name].map { |name| name.to_s.first }.join.upcase
  end
end
