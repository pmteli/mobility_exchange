require "test_helper"

class DesignViewsTest < ActionDispatch::IntegrationTest
  test "home retains prototype landmarks and loads presentation assets" do
    get root_path
    assert_response :success
    assert_select ".compact-home"
    assert_select "header .brand-symbol"
    assert_select ".reference-footer .footer-columns"
    assert_select "#safe-title", text: "Safe Handoff"
    assert_select "script[src*='design-']"
    assert_select "script[src*='app.js']", count: 0
  end

  test "all design previews render without changing stored accounts or exchanges" do
    counts = [ Account.count, Exchange.count, Listing.count ]
    DesignPreviewController::SCREENS.each do |screen|
      get design_preview_path(screen)
      assert_response :success
      assert_select ".preview-notice"
      assert_select "main h1", minimum: 1
    end
    assert_equal counts, [ Account.count, Exchange.count, Listing.count ]
  end

  test "preview template path is allowlisted" do
    get design_preview_path("application")
    assert_response :not_found
  end

  test "donor and recipient tabs have associated panels" do
    %w[donor recipient].each do |screen|
      get design_preview_path(screen)
      panel_ids = css_select("[role=tab]").map { |tab| tab["aria-controls"] }
      assert panel_ids.any?
      panel_ids.each { |id| assert_select "##{id}[role=tabpanel]", count: 1 }
    end
  end
end
