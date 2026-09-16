require "test_helper"
require_relative "../config/smtp_settings"
class SmtpSettingsTest < ActiveSupport::TestCase
  def settings
    { "SMTP_USERNAME" => "sender@example.test", "SMTP_PASSWORD" => "fake-password", "MAIL_FROM" => "sender@example.test", "APP_HOST" => "example.test" }
  end
  test "gmail defaults require encrypted SMTP" do
    config = SmtpSettings.build(settings)
    assert_equal "smtp.gmail.com", config[:address]
    assert_equal 587, config[:port]
    assert_equal :always, config[:enable_starttls]
    assert_equal "peer", config[:openssl_verify_mode]
    assert_not config[:ssl]
  end
  test "implicit TLS and missing secrets are handled" do
    config = SmtpSettings.build(settings.merge("SMTP_TLS_MODE" => "tls"))
    assert_equal 465, config[:port]
    assert config[:ssl]
    assert_not config[:enable_starttls]
    error = assert_raises(ArgumentError) { SmtpSettings.build(settings.except("SMTP_PASSWORD")) }
    assert_includes error.message, "SMTP_PASSWORD"
    assert_raises(ArgumentError) { SmtpSettings.build(settings.merge("SMTP_TLS_MODE" => "none")) }
  end
end
