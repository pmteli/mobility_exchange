class AccountMailer < ActionMailer::Base
  default from: -> { ENV.fetch("MAIL_FROM", "no-reply@example.test") }
  def notification(record)
    @token = record.payload_json.fetch("token")
    @kind = record.template_key
    raise ArgumentError, "Unsupported mail template" unless %w[verification reset email_change].include?(@kind)
    mail(to: record.destination, subject: @kind == "reset" ? "Reset your Mobility Exchange password" : "Verify your Mobility Exchange email")
  end
end
