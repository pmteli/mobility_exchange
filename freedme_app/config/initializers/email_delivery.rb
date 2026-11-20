# Amazon SES SMTP credentials are distinct from ordinary AWS access keys.
Rails.application.config.action_mailer.delivery_method = :test
if ENV["EMAIL_PROVIDER"] == "ses" && !Rails.env.test? && ENV["FREEDME_RECORDING_MODE"] != "true"
  Rails.application.config.action_mailer.delivery_method = :smtp
  Rails.application.config.action_mailer.smtp_settings = {
    address: "email-smtp.#{ENV.fetch('SES_REGION', 'us-west-2')}.amazonaws.com", port: 587,
    domain: ENV.fetch("SES_SMTP_DOMAIN", "freedme.org"), user_name: ENV.fetch("SES_SMTP_USERNAME"),
    password: ENV.fetch("SES_SMTP_PASSWORD"), authentication: :login,
    enable_starttls: true, openssl_verify_mode: "peer", open_timeout: 10, read_timeout: 20
  }
end
