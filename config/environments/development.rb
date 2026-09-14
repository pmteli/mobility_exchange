require_relative "../smtp_settings"
Rails.application.configure do
  config.enable_reloading = true
  config.eager_load = false
  config.consider_all_requests_local = true
  config.cache_store = :memory_store
  if ENV.fetch("MAIL_DELIVERY_METHOD", "file") == "smtp"
    config.action_mailer.delivery_method = :smtp
    config.action_mailer.smtp_settings = SmtpSettings.build
  else
    config.action_mailer.delivery_method = :file
    config.action_mailer.file_settings = { location: Rails.root.join("tmp/mail") }
  end
  config.action_mailer.raise_delivery_errors = true
  config.secret_key_base = "local-development-only-" * 8
end
