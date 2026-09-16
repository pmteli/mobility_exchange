require "test_helper"
class WorkflowTest < ActiveSupport::TestCase
  test "processing evidence, reservation and cancellation obey the database workflow" do
    admin = create_user(role: "admin")
    public_user = create_user
    item = create_item(admin)
    assert_raises(Workflow::Error) { ProcessEquipment.call(public_user, item.id, "awaiting_inspection", "No permission") }
    assert_raises(Workflow::Error) { ProcessEquipment.call(admin, item.id, "available", "Cannot skip inspection") }
    make_available(admin, item)
    assert_equal 2, item.processing_events.count
    request = SubmitRequest.call(public_user, item.id, {})
    assert_raises(Workflow::Error) { ReserveEquipment.call(admin, request.id) }
    Workflow.run { request.update!(status: "approved", reviewed_by: admin.id, reviewed_at: Time.current) }
    ReserveEquipment.call(admin, request.id)
    assert_equal "reserved", item.reload.status_code
    assert_equal 1, request.reservations.where(status: "active").count
    ReserveEquipment.call(admin, request.id)
    assert_equal 1, request.reservations.count
    Workflow.run { request.reservations.first.update!(status: "cancelled", closed_by: admin.id) }
    assert_equal "available", item.reload.status_code
  end
  test "database rejects mutations outside a serializable transaction" do
    assert_raises(ActiveRecord::StatementInvalid) { EquipmentCategory.create!(name: "Unsafe #{SecureRandom.hex(8)}") }
  end
  test "shift capacity cannot be overbooked" do
    admin = create_user(role: "admin")
    users = 2.times.map { create_user(role: "volunteer") }
    shift = Workflow.run do
      users.each { |user| Volunteer.create!(user_id: user.id, approval_status: "approved", approved_by: admin.id, approved_at: Time.current) }
      location = Location.create!(name: "Test Shift Center")
      VolunteerShift.create!(location_id: location.id, activity: "Test shift", starts_at: 1.day.from_now, ends_at: 1.day.from_now + 1.hour, capacity: 1, created_by: admin.id)
    end
    Workflow.run { ShiftSignup.create!(shift_id: shift.id, volunteer_id: users.first.id) }
    assert_raises(Workflow::Error) { Workflow.run { ShiftSignup.create!(shift_id: shift.id, volunteer_id: users.last.id) } }
    assert_equal 1, ShiftSignup.where(shift_id: shift.id).count
  end
end
