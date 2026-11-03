require "test_helper"

class ResourcesFaqTest < ActionDispatch::IntegrationTest
  test "resources preserves help and provides localized frequently asked questions" do
    get "/resources"
    assert_response :success
    assert_select "#panel-mission #mission-statement h2", text: "Mission Statement"
    assert_select "#mission-statement p", text: I18n.t("resources.mission.statement")
    assert_select "footer a[href='/resources#mission-statement']", text: "Mission Statement"
    assert_select "h1", text: "Resources & Help", count: 0
    assert_select "[role=tab][aria-controls=panel-help][aria-selected=true]"
    assert_select "[role=tab][aria-controls=panel-faq]", text: "Questions & Answers"
    assert_select "[role=tab]", count: 4
    assert_select "#tab-mission", text: "Our Mission"
    assert_select "#tab-team", text: "Our Team"
    assert_select "#panel-team[hidden]", text: /Team profiles coming soon/
    assert_select "footer a[href='/resources#panel-team']", text: "Our Team"
    assert_select "#panel-help", text: /Community resource directory preview/
    assert_select "#panel-faq[hidden] details", count: 25
    I18n.t("resources.faqs").each_key do |key|
      assert_select "#faq-#{key} summary", text: I18n.t("resources.faqs.#{key}.question")
      assert_select "#faq-#{key} p", text: I18n.t("resources.faqs.#{key}.answer", website: "https://www.freedme.org")
    end
    assert_not_includes response.body, "%{website}"
  end
end
