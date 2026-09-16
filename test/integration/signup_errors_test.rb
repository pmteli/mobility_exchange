require "test_helper"
class SignupErrorsTest < ActionDispatch::IntegrationTest
  test "rate limit renders the signup form instead of a blank browser error" do
    store = RegistrationsController.cache_store
    original = store.method(:increment)
    store.define_singleton_method(:increment) { |*args, **options| 6 }
    assert_no_difference "User.count" do
      post registration_path, params: {first_name: "Alex", email: "alex@example.test", community_roles: ["donor"]}
    end
    assert_response :too_many_requests
    assert_equal "3600", response.headers["Retry-After"]
    assert_select "form #signup-errors", text: /Too many signup attempts/
    assert_select "input[name=first_name][value=Alex]"
  ensure
    store.define_singleton_method(:increment, original) if original
  end

  test "invalid signup stays in the form and preserves non-secret fields" do
    attrs = {first_name: "Alex", last_name: "User", email: "signup-#{SecureRandom.hex(8)}@example.test", password: "short", password_confirmation: "different", community_roles: ["donor", "recipient"]}
    assert_no_difference ["User.count", "Credential.count", "Notification.count"] do
      post registration_path, params: attrs
    end
    assert_response :unprocessable_entity
    assert_select "form #signup-errors[role=alert] li", minimum: 1
    %i[first_name last_name email].each { |field| assert_select "input[name='#{field}'][value='#{attrs[field]}']" }
    assert_select "input[value=donor][checked]"
    assert_select "input[value=recipient][checked]"
    assert_select "input[type=password][value]", count: 0
    assert_select "fieldset + #signup-errors"
  end

  test "duplicate email and missing roles show errors inside signup form" do
    existing = create_user
    attrs = {first_name: "Alex", last_name: "User", email: existing.email, password: "12345678", password_confirmation: "12345678", community_roles: ["donor"]}
    post registration_path, params: attrs
    assert_response :unprocessable_entity
    assert_select "form #signup-errors", text: /Email has already been taken/
    post registration_path, params: attrs.merge(community_roles: [])
    assert_response :unprocessable_entity
    assert_select "form #signup-errors", text: /Select at least one role/
  end
end
