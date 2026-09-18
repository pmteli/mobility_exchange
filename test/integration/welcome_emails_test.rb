require "test_helper"
class WelcomeEmailsTest < ActionDispatch::IntegrationTest
  test "verification queues role welcomes once with appropriate next steps" do
    user = Signup.call(email: "welcome-#{SecureRandom.hex(8)}@example.test", first_name: "Alex", last_name: "User", password: "12345678", password_confirmation: "12345678", community_roles: %w[donor volunteer])
    scope = Notification.where(recipient_user_id: user.id, template_key: %w[welcome_donor welcome_volunteer])
    assert_equal 0, scope.count
    token = AccountTokens.issue(user, "verify")
    post verification_path(token)
    assert_redirected_to new_session_path
    assert_equal 2, scope.count
    scope.each do |record|
      mail = AccountMailer.notification(record).message
      assert_equal [user.email], mail.to
      assert_includes mail.html_part.body.decoded, "mobility-exchange-email-branded-hero.png"
      assert_includes mail.text_part.body.decoded, "Hi Alex"
      path = record.template_key == "welcome_donor" ? new_donation_path : new_volunteer_application_path
      assert_includes mail.text_part.body.decoded, path
    end
    assert_includes AccountMailer.notification(scope.find_by!(template_key: "welcome_volunteer")).message.text_part.body.decoded, "approval is required"
    post verification_path(token)
    assert_response :not_found
    assert_equal 2, scope.count
  end
end
