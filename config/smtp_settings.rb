# Explicit TLS modes support STARTTLS (usually 587) and implicit TLS (usually 465).
module SmtpSettings
  def self.build(env = ENV)
    required = %w[SMTP_USERNAME SMTP_PASSWORD MAIL_FROM APP_HOST]
    missing = required.select { |key| env[key].to_s.strip.empty? }
    raise ArgumentError, "Missing email configuration: #{missing.join(', ')}" if missing.any?
    mode = env.fetch("SMTP_TLS_MODE", "starttls")
    raise ArgumentError, "SMTP_TLS_MODE must be starttls or tls" unless %w[starttls tls].include?(mode)
    port = Integer(env.fetch("SMTP_PORT", mode == "tls" ? "465" : "587"))
    raise ArgumentError, "Invalid SMTP_PORT" unless (1..65535).cover?(port)
    authentication = env.fetch("SMTP_AUTHENTICATION", "plain")
    raise ArgumentError, "SMTP_AUTHENTICATION must be plain or login" unless %w[plain login].include?(authentication)
    {
      address: env.fetch("SMTP_HOST", "smtp.gmail.com"), port: port,
      domain: env.fetch("SMTP_DOMAIN", env.fetch("APP_HOST")),
      user_name: env.fetch("SMTP_USERNAME"), password: env.fetch("SMTP_PASSWORD"),
      authentication: authentication.to_sym,
      enable_starttls: mode == "starttls" ? :always : false, enable_starttls_auto: false,
      ssl: mode == "tls", openssl_verify_mode: "peer",
      open_timeout: 10, read_timeout: 20
    }
  end
end
