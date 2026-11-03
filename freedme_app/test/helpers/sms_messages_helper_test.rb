require "test_helper"

class SmsMessagesHelperTest < ActionView::TestCase
  include SmsMessagesHelper

  test "short SMS URLs become clickable links" do
    html = sms_message_body("Review http://localhost:3001/s/requests")
    assert_includes html, '<a href="http://localhost:3001/s/requests">http://localhost:3001/s/requests</a>'
  end

  test "message content remains escaped" do
    html = sms_message_body('<script>alert(1)</script> https://freedme.org/s/qa')
    refute_includes html, '<script>'
    assert_includes html, '&lt;script&gt;'
    assert_includes html, '<a href="https://freedme.org/s/qa">'
  end
end
