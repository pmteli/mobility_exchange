require "test_helper"
class PasswordResetErrorsTest < ActionDispatch::IntegrationTest
  test "mismatch stays below title and allows retry with same token" do
    user = create_user
    token = AccountTokens.issue(user, "reset")
    login = Authentication.login(email: user.email, password: "correct horse battery staple", otp: "")
    patch password_reset_path(token), params: {password: "replacement password", password_confirmation: "different password"}
    assert_response :unprocessable_entity
    assert_select "h1 + #password-reset-errors.signup-error-summary[role=alert]", text: /doesn't match Password/
    assert_select "form[action=?]", password_reset_path(token)
    assert_select "input[type=password][value]", count: 0
    assert AccountTokens.resolve(token, "reset")
    assert LoginSession.exists?(login.id)
    assert user.credential.reload.authenticate("correct horse battery staple")
    patch password_reset_path(token), params: {password: "replacement password", password_confirmation: "replacement password"}
    assert_redirected_to new_session_path
    assert_nil AccountTokens.resolve(token, "reset")
    assert_not LoginSession.exists?(login.id)
    assert user.credential.reload.authenticate("replacement password")
  end
end
