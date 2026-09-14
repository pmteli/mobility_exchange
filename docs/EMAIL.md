# Email delivery

Verification, resend-verification, and password-reset messages use the database outbox and a separate `bin/notifications` worker. Emails include HTML and plain-text versions. No provider credentials are bundled.

## Connect an SMTP provider

Configure these variables in the environment for **both web and worker** processes:

- `MAIL_DELIVERY_METHOD=smtp` (required to opt into SMTP in development; production always uses SMTP).
- `MAIL_FROM`: a sender address verified with your provider.
- `SMTP_HOST`, `SMTP_USERNAME`, `SMTP_PASSWORD`: provider-issued SMTP settings. Use a provider SMTP credential or app password as supported by the provider, not credentials pasted into chat.
- `SMTP_PORT=587`, `SMTP_TLS_MODE=starttls`; for implicit TLS use port `465` and mode `tls`.
- `SMTP_AUTHENTICATION=plain` or `login`, as required by the provider.
- `APP_HOST` and `APP_PORT`: the address users will open from email links. Production uses HTTPS; local development uses HTTP. The local preview uses `APP_HOST=127.0.0.1` and `APP_PORT=3100`. Localhost links only work on the machine running the app.

Restart both processes after changing configuration. For a shell-based installation, export variables securely before starting Rails and `bundle exec bin/notifications`. Rails does not automatically load `.env.example`. Docker Compose forwards these variables to both services; use `docker compose up -d --build web worker` after configuration. Never commit credentials. The Compose setup remains local development only.

SMTP uses TLS with certificate verification and connection/read timeouts. Missing required settings fail at startup. Providers that require OAuth rather than SMTP username/password need a separate provider integration.

## Verify delivery

After setup, register your own test address or request a password reset for it. The worker sends eligible messages automatically. For one batch, run `bin/rails mobility:deliver_notifications`. Check the inbox and spam folder. A `sent` outbox status means the SMTP server accepted the message, not that inbox delivery is guaranteed. Configure the provider's required domain verification, SPF, and DKIM records.

Failed deliveries retry with backoff, up to five attempts. Outbox `last_error` stores only the exception class; credentials are not logged. Monitor failed records. Delivery is at least once: a crash after SMTP acceptance can cause a duplicate.

Without SMTP enabled, development keeps messages in `tmp/mail`. Tests use an in-memory mail delivery adapter and never send external mail. Live provider delivery requires configuration and has not been verified in this package.

## Gmail setup

Use `SMTP_HOST=smtp.gmail.com`, `SMTP_PORT=587`, `SMTP_TLS_MODE=starttls`, and `SMTP_AUTHENTICATION=plain`. Set `SMTP_USERNAME` and `MAIL_FROM` to your full Gmail address. Enable 2-Step Verification on that Google account and generate an App Password for Mobility Exchange; store it as `SMTP_PASSWORD` in your local environment or deployment secret manager. Do not use your normal Google password. This Google account requirement does not enable MFA for application users.

App Password availability depends on account settings and organization policy. If unavailable, ask the account administrator or use an OAuth integration instead. Do not disable account security settings to work around policy.

Official references: [Gmail SMTP settings](https://support.google.com/mail/answer/7104828?hl=en) and [Google App Passwords](https://support.google.com/mail/answer/185833?hl=en).

### Mobility Exchange sender

The supplied sender configuration is `admin@mobilityexchange.org`, using `smtp.gmail.com:587` with STARTTLS and authentication. Set both `SMTP_USERNAME` and `MAIL_FROM` to this address. The Google Workspace account must allow App Passwords. The password has not been provided or stored, so live delivery remains inactive.
