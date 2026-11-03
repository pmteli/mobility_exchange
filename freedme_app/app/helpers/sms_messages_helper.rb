module SmsMessagesHelper
  def sms_message_body(body)
    # safe_join escapes message text; link_to escapes both the label and URL.
    parts = body.to_s.split(%r{(https?://[^\s<>"']+/s/(?:home|find|items|requests|qa|login)\b)})
    safe_join(parts.each_with_index.map do |part, index|
      index.odd? ? link_to(part, part) : part
    end)
  end
end
