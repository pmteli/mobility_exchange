require "test_helper"
class ProfilesTest < ActionDispatch::IntegrationTest
  PASSWORD = "correct horse battery staple"
  test "profile requires login and restricts updates to the signed in user" do
    get edit_account_path
    assert_redirected_to new_session_path
    user = create_user
    other = create_user
    post session_path, params: {email: user.email, password: PASSWORD}
    get edit_account_path
    assert_response :success
    patch account_path, params: {user: {id: other.id, first_name: "Updated", last_name: "Person", email: user.email, phone: "555-0100", address_line1: "123 Main St", address_line2: "Unit 2", city: "San Jose", region: "CA", postal_code: "95112", account_status: "suspended", community_roles: ["admin"]}}
    assert_redirected_to account_path
    user.reload
    assert_equal "Updated", user.first_name
    assert_equal "123 Main St", user.address_line1
    assert_equal "active", user.account_status
    assert_not_includes user.community_roles, "admin"
    assert_equal "Test", other.reload.first_name
    patch account_path, params: {user: {first_name: "", city: "Must not save", email: user.email}}
    assert_response :unprocessable_entity
    assert_equal "San Jose", user.reload.city
  end

  test "email change requires password and confirmation and revokes sessions" do
    user = create_user
    original = user.email
    replacement = "new-#{SecureRandom.hex(8)}@example.test"
    post session_path, params: {email: original, password: PASSWORD}
    patch account_path, params: {user: {email: replacement}}
    assert_response :unprocessable_entity
    assert_nil user.reload.pending_email
    patch account_path, params: {user: {email: replacement}, current_password: PASSWORD}
    assert_redirected_to account_path
    assert_equal original, user.reload.email
    assert_equal replacement, user.pending_email
    notification = Notification.where(recipient_user_id: user.id, template_key: "email_change").last!
    token = notification.payload_json.fetch("token")
    mail = AccountMailer.notification(notification).message
    assert_includes mail.text_part.body.decoded, profile_email_path(token)
    get profile_email_path(token)
    assert_response :success
    assert_equal original, user.reload.email
    patch account_path, params: {user: {first_name: "Still editable", email: replacement}}
    assert_redirected_to account_path
    assert_equal "Still editable", user.reload.first_name
    post profile_email_path(token)
    assert_redirected_to new_session_path
    assert_equal replacement, user.reload.email
    assert_nil user.pending_email
    assert_equal 0, LoginSession.where(user_id: user.id).count
    post profile_email_path(token)
    assert_response :not_found
  end

  test "profile changes sync linked contacts without clearing unrelated information" do
    user = create_user
    contacts = Workflow.run do
      [Donor, Recipient].map { |model| model.create!(user_id: user.id, first_name: user.first_name, last_name: user.last_name, email: user.email, address_line1: "Existing address") }
    end
    UpdateProfile.call(user, {first_name: "New name", phone: "555-1234"}, current_password: nil)
    contacts.each do |contact|
      assert_equal "New name", contact.reload.first_name
      assert_equal "555-1234", contact.phone
      assert_equal "Existing address", contact.address_line1
    end
    UpdateProfile.call(user, {address_line1: "New address", city: "Oakland"}, current_password: nil)
    contacts.each { |contact| assert_equal "New address", contact.reload.address_line1 }
  end

  test "duplicate emails and expired confirmation links cannot change identity" do
    user = create_user
    other = create_user
    assert_raises(Workflow::Error) { UpdateProfile.call(user, {email: other.email}, current_password: PASSWORD) }
    UpdateProfile.call(user, {email: "new-#{SecureRandom.hex(8)}@example.test"}, current_password: PASSWORD)
    token = Notification.where(recipient_user_id: user.id, template_key: "email_change").last!.payload_json.fetch("token")
    travel 25.hours do
      assert_nil UpdateProfile.resolve(token)
    end
    UpdateProfile.call(user, {email: user.email}, current_password: nil)
    assert_nil UpdateProfile.resolve(token)
  end
end
