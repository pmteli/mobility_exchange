class AccountMailer < ActionMailer::Base
  default from: -> { ENV.fetch("MAIL_FROM", "no-reply@example.test") }
  def notification(record)
    @token = record.payload_json.fetch("token")
    @kind = record.template_key
    raise ArgumentError, "Unsupported mail template" unless %w[verification reset].include?(@kind)
    mail(to: record.destination, subject: @kind == "verification" ? "Verify your Mobility Exchange email" : "Reset your Mobility Exchange password")
  end
end
