require "test_helper"

class MessagingPoliciesTest < ActionDispatch::IntegrationTest
  test "policy pages are available without sign in and cross link" do
    %w[privacy sms-terms sms-consent].each do |page|
      get "/#{page}.html"
      assert_response :success
      assert_select "h1", count: 1
      assert_select "a[href='privacy.html']"
      assert_select "a[href='sms-terms.html']"
      assert_includes response.body, "Mobility Exchange"
      assert_not_includes response.body, "Mobility Exchange LLC"
    end
    get "/privacy.html"
    assert_select "a[href='mailto:inquiry@mobilityexchange.org']"
  end

  test "registration consent is optional unchecked and links to policies" do
    get "/register"
    assert_response :success
    assert_select "input[name=sms_consent][type=checkbox]", count: 1
    assert_select "input[name=sms_consent][checked]", count: 0
    assert_select "input[name=sms_consent][required]", count: 0
    assert_select "a[href='/privacy.html']"
    assert_select "a[href='/sms-terms.html']"
    assert_includes response.body, I18n.t("messaging_consent.optional")
  end
end
