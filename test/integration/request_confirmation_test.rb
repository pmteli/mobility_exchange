require "test_helper"
class RequestConfirmationTest < ActionDispatch::IntegrationTest
  test "successful request queues confirmation with public details and pickup steps" do
    admin = create_user(role: "admin")
    recipient = create_user
    item = make_available(admin, create_item(admin))
    record = SubmitRequest.call(recipient, item.id, {})
    notifications = Notification.where(template_key: "equipment_request_confirmation", recipient_user_id: recipient.id)
    assert_equal 1, notifications.count
    note = notifications.first
    assert_equal recipient.email, note.destination
    assert_equal record.id, note.payload_json.fetch("request_id")
    mail = AccountMailer.notification(note).message
    [mail.html_part.body.decoded, mail.text_part.body.decoded].each do |body|
      assert_includes body, item.name
      assert_includes body, item.inventory_number
      assert_includes body, record.reference_number
      assert_includes body, equipment_request_path(record)
      assert_includes body, "waiver"
      assert_includes body, "not yet reserved"
      assert_not_includes body, "PRIVATE-NEVER-PUBLIC"
    end
    unavailable = create_item(admin)
    assert_no_difference "Notification.count" do
      assert_raises(ActiveRecord::RecordNotFound) { SubmitRequest.call(recipient, unavailable.id, {}) }
    end
  end
end
