require "test_helper"

class SmsLinksTest < ActionDispatch::IntegrationTest
  test "public links redirect to the catalog" do
    get "/s/find"
    assert_redirected_to "/equipment"
  end

  test "private links require login and preserve the activity tab" do
    get "/s/qa"
    assert_redirected_to sign_in_path
    assert_equal "/activity#panel-questions", session[:return_to]
  end

  test "unknown destinations cannot redirect externally" do
    get "/s/unknown", params: {url: "https://example.com"}
    assert_response :not_found
  end
end
