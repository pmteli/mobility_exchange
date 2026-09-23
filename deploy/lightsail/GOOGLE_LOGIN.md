# Google sign-in (Alpha3.0)

Email/password authentication remains available. Google buttons appear only when all three Google environment settings are present. No Google password, access token, or refresh token is stored. The stable Google `sub` identifier is stored in `users.google_subject`, with a unique index.

## Create the Google client

1. Open https://console.cloud.google.com/auth/overview and select or create a project for Mobility Exchange.
2. Configure Branding with the app name **Mobility Exchange**, support email, developer contact email, and the real homepage/privacy-policy URLs requested by Google. Do not invent a privacy policy URL.
3. Under Audience select External and, during testing, add the Google accounts that will test sign-in.
4. Create an OAuth client under Clients, application type **Web application**.
5. Add the exact authorized redirect URI: `https://test.mobilityexchange.org/auth/google/callback`.
6. Only `openid email profile` scopes are requested. No Gmail or Drive permissions are needed.
7. Store the client ID and secret using the server helper below, not in Git or chat. This OAuth client secret is different from the Gmail SMTP App Password.

## Deployment and configuration

Deploy the application build, then run the migration before restarting web/worker:

```bash
cd /home/ubuntu/mobility-exchange/deploy/lightsail
sudo docker compose build web
sudo docker compose run --rm --no-deps web bin/rails db:migrate
python3 configure_google_login.py
sudo docker compose up -d --force-recreate web worker
```

The helper privately prompts for the OAuth credentials and updates only the Google settings in `.env`, escaping Compose interpolation. It never prints the secret. To disable Google login, clear `GOOGLE_CLIENT_SECRET` and recreate web/worker; existing password login continues to work.

## Behavior and verification

- Start uses a CSRF-protected POST. The callback validates an expiring browser-bound state and exchanges the single-use code using PKCE. Google's official `googleauth` library verifies the ID token's signature, issuer, audience and expiry; the application also verifies nonce and verified email.
- Tokens are discarded after verification. State, codes, passwords and tokens are filtered from Rails logs.
- Linked accounts are found by Google subject, not email. Suspended/archived accounts cannot sign in.
- A new user confirms names and chooses Donor, Volunteer and/or Recipient. They receive only the `public` permission role, not staff access or volunteer approval. Donor/volunteer welcome notifications use the existing outbox.
- A matching existing email requires the local account password and active, verified status before linking. An email match never silently links accounts.
- New Google users can set a local password using the existing password-reset flow.
- Successful authentication rotates the session and creates the normal 12-hour login session.

After configuring real credentials, test: new signup and role selection, returning Google login, existing-account password linking, cancellation, and ordinary email/password login. Automated tests use synthetic identities; an end-to-end Google consent flow still requires the actual OAuth client and a test account.

References: https://developers.google.com/identity/openid-connect/openid-connect and https://docs.cloud.google.com/ruby/docs/reference/googleauth/latest/Google-Auth-IDTokens
