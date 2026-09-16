require "test_helper"
class AccessTest < ActionDispatch::IntegrationTest
  test "catalog uses only available equipment and never includes private notes" do
    admin = create_user(role: "admin")
    item = create_item(admin)
    get catalog_item_path(item)
    assert_response :not_found
    make_available(admin, item)
    get root_path(q: "Test wheelchair")
    assert_response :success
    assert_includes response.body, "Test wheelchair"
    assert_not_includes response.body, "PRIVATE-NEVER-PUBLIC"
    get catalog_item_path(item)
    assert_response :success
    assert_not_includes response.body, "PRIVATE-NEVER-PUBLIC"
  end
  test "public account cannot enter staff operations or read another user's request" do
    admin = create_user(role: "admin")
    owner = create_user
    other = create_user
    item = make_available(admin, create_item(admin))
    record = SubmitRequest.call(owner, item.id, {})
    post session_path, params: { email: other.email, password: "correct horse battery staple" }
    assert_redirected_to account_path
    get staff_root_path
    assert_response :forbidden
    get equipment_request_path(record)
    assert_response :not_found
    patch staff_request_path(record), params: { status: "approved" }
    assert_response :forbidden
    assert_equal "submitted", record.reload.status
  end
  test "unverified account cannot sign in" do
    user = create_user(verified: false)
    post session_path, params: { email: user.email, password: "correct horse battery staple" }
    assert_response :unprocessable_entity
    get account_path
    assert_redirected_to new_session_path
  end
  test "administrator signs in without an authenticator even with a saved secret" do
    admin = create_user(role: "admin")
    Workflow.run { admin.credential.update!(mfa_secret: ROTP::Base32.random) }
    post session_path, params: { email: admin.email, password: "correct horse battery staple" }
    assert_redirected_to account_path
    get staff_root_path
    assert_response :success
  end
  test "password minimum is eight characters" do
    user = create_user
    credential = user.credential
    credential.password = credential.password_confirmation = "1234567"
    assert_not credential.valid?
    credential.password = credential.password_confirmation = "12345678"
    assert credential.valid?
    get new_session_path
    assert_select "input[name=otp]", count: 0
    get new_registration_path
    assert_select "input[name=password][minlength='8']"
    assert_select "input[type=checkbox][name='community_roles[]'][value=recipient]"
  end
  test "registration ignores supplied staff roles" do
    email = "signup-#{SecureRandom.hex(8)}@example.test"
    post registration_path, params: { email: email, first_name: "New", last_name: "User", password: "correct horse battery staple", password_confirmation: "correct horse battery staple", community_roles: ["donor"], role: "admin", account_status: "active" }
    assert_response :redirect
    user = User.find_by!(email: email)
    assert_equal "pending", user.account_status
    assert_equal ["public"], user.user_roles.pluck(:role_id)
    assert_equal 1, Notification.where(recipient_user_id: user.id, template_key: "verification").count
  end
  test "signup accepts all community role combinations without staff permissions" do
    %w[volunteer donor recipient].then { |roles| (1..3).flat_map { |size| roles.combination(size).to_a } }.each do |roles|
      user = Signup.call(email: "roles-#{SecureRandom.hex(8)}@example.test", first_name: "New", last_name: "User", password: "12345678", password_confirmation: "12345678", community_roles: roles)
      assert_equal roles, user.reload.community_roles
      assert_equal ["public"], user.user_roles.pluck(:role_id)
    end
    [[], ["admin"], ["volunteer", "board"]].each do |roles|
      assert_no_difference "User.count" do
        assert_raises(Workflow::Error) { Signup.call(community_roles: roles) }
      end
    end
  end
  test "password reset invalidates tokens and sessions" do
    user = create_user
    token = AccountTokens.issue(user, "reset")
    login = Authentication.login(email: user.email, password: "correct horse battery staple", otp: "")
    patch password_reset_path(token), params: { password: "a different strong password", password_confirmation: "a different strong password" }
    assert_response :redirect
    assert_nil AccountTokens.resolve(token, "reset")
    assert_not LoginSession.exists?(login.id)
    assert user.credential.reload.authenticate("a different strong password")
  end
end
