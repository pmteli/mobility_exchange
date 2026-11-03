require "test_helper"

class HowItWorksTest < ActionDispatch::IntegrationTest
  test "document content replaces old guide while preserving section links" do
    get "/how-it-works"
    assert_response :success
    assert_select "h1", text: "How it works"
    assert_select "#connect ol > li", count: 5
    assert_select "#receiving ol > li", count: 5
    assert_select "#receiving li:nth-child(2)", text: /A caregiver or community helper/
    assert_select "#handoff", text: /Home handoffs are not permitted/
    assert_select "#protection h2", text: "Help protect the community"
    assert_select "#response-times", text: /24 hours to accept/
    assert_not_includes response.body, "Details of other reminders, listing freshness and loan timing remain open"
  end
end
