require "test_helper"
class PagesHelperTest < ActionView::TestCase
  include PagesHelper
  test "formats FAQ labels and bullets while escaping HTML" do
    html = page_content("**Question: Get involved?**\n\n- **For Donors:** Donate.\n- **For Volunteers:** Help.\n\n<script>alert(1)</script>")
    assert_includes html, "<strong>Question: Get involved?</strong>"
    assert_includes html, "<ul><li><strong>For Donors:</strong> Donate.</li>"
    assert_includes html, "&lt;script&gt;"
    assert_not_includes html, "<script>"
  end
end
