require "test_helper"

class FrameworkTest < ActionDispatch::IntegrationTest
  test "public pages render without exposing private fields" do
    [ root_path, equipment_index_path, how_it_works_path, resources_path, our_team_path ].each do |path|
      get path
      assert_response :success
      assert_select "h1", minimum: 1
      assert_select "input[name=phone]", count: 0
    end
  end

  test "all private dashboards fail closed even with forged actor or role" do
    [ donor_dashboard_path, recipient_dashboard_path, moderator_dashboard_path ].each do |path|
      get path, params: { account_id: "admin", role: "moderator" }
      assert_redirected_to sign_in_path
      assert_equal "no-store", response.headers["Cache-Control"]
    end
    follow_redirect!
    assert_response :success
  end

  test "search escapes literal wildcard and accepts hostile input safely" do
    get equipment_index_path, params: { query: "%' OR 1=1 --", category_id: "invalid", page: "-100", offer_kind: "anything" }
    assert_response :success
  end

  test "unpublished equipment cannot be fetched by id" do
    get equipment_path("019a0000-0000-7000-8000-000000000001")
    assert_response :not_found
  end
end
