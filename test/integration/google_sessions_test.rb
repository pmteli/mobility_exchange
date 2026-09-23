require "test_helper"
class GoogleSessionsTest < ActionDispatch::IntegrationTest
  setup do
    @env = ENV.to_h.slice("GOOGLE_CLIENT_ID", "GOOGLE_CLIENT_SECRET", "GOOGLE_REDIRECT_URI")
    ENV.update("GOOGLE_CLIENT_ID" => "test-client", "GOOGLE_CLIENT_SECRET" => "test-secret", "GOOGLE_REDIRECT_URI" => "https://test.mobilityexchange.org/auth/google/callback")
    @identity = { "sub" => SecureRandom.uuid, "email" => "google-#{SecureRandom.hex(8)}@example.test", "first_name" => "Google", "last_name" => "User" }
  end
  teardown do
    %w[GOOGLE_CLIENT_ID GOOGLE_CLIENT_SECRET GOOGLE_REDIRECT_URI].each { |k| ENV.delete(k) }
    ENV.update(@env)
  end

  def google_callback(identity = @identity)
    post google_sign_in_path
    assert_response :redirect
    query = URI.decode_www_form(URI(response.location).query).to_h
    assert_equal "openid email profile", query["scope"]
    assert_equal "S256", query["code_challenge_method"]
    assert query["nonce"].present?
    original = GoogleOauth.method(:identity)
    GoogleOauth.define_singleton_method(:identity) { |**args| identity }
    get "/auth/google/callback", params: { state: query["state"], code: "test-code" }
  ensure
    GoogleOauth.define_singleton_method(:identity, original) if original
  end

  test "Google signup requires roles, creates verified public user and permits subsequent login" do
    assert_no_difference "User.count" do
      google_callback
      assert_redirected_to new_google_registration_path
    end
    post google_registration_path, params: { first_name: "Alex", last_name: "User", community_roles: ["admin"] }
    assert_response :unprocessable_entity
    assert_select ".signup-error-summary"
    assert_difference "User.count", 1 do
      post google_registration_path, params: { first_name: "Alex", last_name: "User", community_roles: ["donor", "volunteer", "recipient"] }
    end
    assert_redirected_to account_path
    user = User.find_by!(google_subject: @identity["sub"])
    assert_equal "active", user.account_status
    assert user.email_verified_at
    assert_equal ["public"], user.user_roles.pluck(:role_id)
    assert_nil user.volunteer
    assert_equal 2, Notification.where(recipient_user_id: user.id).count
    delete session_path
    google_callback(@identity.merge("email" => "changed@example.test"))
    assert_redirected_to account_path
    assert_equal @identity["email"], user.reload.email
  end

  test "existing email is linked only after correct local password" do
    user = create_user
    @identity["email"] = user.email
    google_callback
    assert_nil user.reload.google_subject
    get new_google_registration_path
    assert_select "input[type=password]"
    post google_registration_path, params: { password: "wrong" }
    assert_response :unprocessable_entity
    assert_nil user.reload.google_subject
    post google_registration_path, params: { password: "correct horse battery staple", community_roles: ["admin"] }
    assert_redirected_to account_path
    assert_equal @identity["sub"], user.reload.google_subject
    assert_not user.admin?
    assert Authentication.login(email: user.email, password: "correct horse battery staple")
  end

  test "suspended linked account cannot sign in" do
    user = create_user
    MobilityTransaction.call { user.update!(google_subject: @identity["sub"], account_status: "suspended") }
    assert_no_difference "LoginSession.count" do
      google_callback
      assert_redirected_to new_session_path
    end
  end

  test "invalid state and cancelled callbacks do not authenticate" do
    post google_sign_in_path
    state = URI.decode_www_form(URI(response.location).query).to_h["state"]
    get "/auth/google/callback", params: { state: "wrong", code: "anything" }
    assert_redirected_to new_session_path
    get "/auth/google/callback", params: { state: state, error: "access_denied" }
    assert_redirected_to new_session_path
    post google_registration_path, params: { email: @identity["email"], community_roles: ["donor"] }
    assert_redirected_to new_session_path
  end

  test "pending Google identity expires" do
    google_callback
    travel 11.minutes do
      post google_registration_path, params: { first_name: "Alex", last_name: "User", community_roles: ["donor"] }
      assert_redirected_to new_session_path
    end
  end

  test "Google button is conditional and email password forms remain" do
    get new_session_path
    assert_select "form[action=?]", google_sign_in_path
    assert_select "input[type=password]"
    ENV.delete("GOOGLE_CLIENT_SECRET")
    get new_session_path
    assert_select "form[action=?]", google_sign_in_path, count: 0
    assert_select "input[type=password]"
    post google_sign_in_path
    assert_redirected_to new_session_path
  end
end
