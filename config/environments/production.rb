require_relative "../smtp_settings"
Rails.application.configure do
  config.enable_reloading = false
  config.eager_load = true
  config.consider_all_requests_local = false
  config.force_ssl = true
  config.public_file_server.enabled = true
  config.log_level = :info
  config.secret_key_base = ENV.fetch("SECRET_KEY_BASE")
  config.hosts = [ENV.fetch("APP_HOST")]
  config.cache_store = :redis_cache_store, { url: ENV.fetch("REDIS_URL") }
  config.action_mailer.raise_delivery_errors = true
  if ENV["DEPLOYMENT_STAGE"] == "test" && ENV["MAIL_DELIVERY_METHOD"] == "file"
    config.action_mailer.delivery_method = :file
    config.action_mailer.file_settings = { location: Rails.root.join("tmp/mail") }
  else
    config.action_mailer.delivery_method = :smtp
    config.action_mailer.smtp_settings = SmtpSettings.build
  end
end
