require "test_helper"
class ShiftLocationsTest < ActionDispatch::IntegrationTest
  test "location tabs filter dated shifts and select a valid default" do
    user = create_user(role: "admin")
    places = Workflow.run do
      %w[First Second].map do |name|
        place = Location.create!(name: "#{name} #{SecureRandom.hex(4)}")
        VolunteerShift.create!(location_id: place.id, activity: "Shift at #{place.name}", starts_at: 2.days.from_now, ends_at: 2.days.from_now + 4.hours, capacity: 3, created_by: user.id)
        place
      end
    end
    post session_path, params: {email: user.email, password: "correct horse battery staple"}
    places.each do |place|
      get shifts_path(location_id: place.id)
      assert_response :success
      assert_select 'nav[aria-label="Shift locations"] a[aria-current=page]', text: place.name
      assert_select '.card h3', text: "Shift at #{place.name}"
      other = (places - [place]).first
      assert_select '.card h3', text: "Shift at #{other.name}", count: 0
    end
    get shifts_path(location_id: "missing")
    assert_response :success
    assert_select '.shift-location-tab[aria-current=page]', count: 1
  end
end
