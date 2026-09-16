require_relative "boot"
require "rails"
require "active_model/railtie"
require "active_record/railtie"
require "action_controller/railtie"
require "action_view/railtie"
require "action_mailer/railtie"
require "rails/test_unit/railtie"
Bundler.require(*Rails.groups)
module MobilityExchange
  class Application < Rails::Application
    config.load_defaults 8.1
    config.time_zone = "UTC"
    config.active_record.schema_format = :sql
    config.active_record.dump_schemas = :all
    config.active_record.encryption.primary_key = ENV.fetch("ENCRYPTION_PRIMARY_KEY") { Rails.env.production? ? raise("ENCRYPTION_PRIMARY_KEY required") : "development-only-primary-key-0001" }
    config.active_record.encryption.deterministic_key = ENV.fetch("ENCRYPTION_DETERMINISTIC_KEY") { Rails.env.production? ? raise("ENCRYPTION_DETERMINISTIC_KEY required") : "development-only-deterministic-01" }
    config.active_record.encryption.key_derivation_salt = ENV.fetch("ENCRYPTION_KEY_DERIVATION_SALT") { Rails.env.production? ? raise("ENCRYPTION_KEY_DERIVATION_SALT required") : "development-only-salt-00000000001" }
    config.filter_parameters += [:password, :password_confirmation, :otp, :token, :signature, :date_of_birth, :private_notes, :mfa_secret, :email, :phone, :address_line1]
    config.action_dispatch.cookies_same_site_protection = :lax
    config.action_mailer.default_url_options = { host: ENV.fetch("APP_HOST", "localhost"), port: ENV.fetch("APP_PORT", "3000"), protocol: Rails.env.production? ? "https" : "http" }
  end
end
