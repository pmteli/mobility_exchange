# Twilio integration — prepared, not activated

Requirements: FR003 (verified sign-in/registration), FR018/FR027 (queued notifications), FR020 (consent), G02 messaging gap. DEC05 recovery/retry policies remain unresolved. This does not authorize a production launch.

Default: `SMS_PROVIDER=simulated`. No credentials have been installed, live messages sent, or Lightsail configuration changed. Recording instances force simulation regardless of provider selection. Existing journey guards still restrict full production operation to the explicitly configured hosted demo; this integration does not remove those guards or replace the separate staff-authentication requirement.

## Configuration after business/brand/campaign approval

Set these through deployment secrets, never Git:

```
SMS_PROVIDER=twilio
TWILIO_ACCOUNT_SID=AC...
TWILIO_AUTH_TOKEN=...
TWILIO_VERIFY_SERVICE_SID=VA...
TWILIO_MESSAGING_SERVICE_SID=MG...
TWILIO_WEBHOOK_BASE_URL=https://your-approved-app-host
SMS_LINK_BASE_URL=https://your-approved-app-host
```

Run migrations and restart both Rails and the journey worker. Configure Verify for six-digit SMS codes. Configure Messaging Service with an approved sender and Advanced Opt-Out; enable incoming webhooks (do not drop incoming messages):

- POST `/webhooks/twilio/incoming`
- Status callback POST `/webhooks/twilio/status`

Use exactly the HTTPS host configured above, with no URL query parameters. Webhooks validate HMAC-SHA1 signatures over the configured public URL and all form parameters, plus Account SID. Any reverse proxy/basic-auth gate must allow these two paths through to Rails; Rails authenticates them with the Twilio signature. Do not disable authentication for other pages. Public campaign consent, privacy, and terms pages still need review before activation.

## Behavior

- OTPs use Twilio Verify, not our notification catalog. Rails retains expiry, three failed attempts, per-phone resend limits and account creation only after verification. Local codes cannot authenticate after switching to live mode.
- Notification bodies retain the existing en.yml catalog and first-party links. Live messages append STOP instructions. Outbox writes occur inside the existing transaction; the worker reads committed rows. Recipient and message body are encrypted at rest using the existing application encryption helper.
- Each idempotency key queues once. Consent is checked at dispatch. No routine-SMS consent means suppressed, including welcome SMS. Registration has an optional unchecked consent checkbox; existing members can update preferences in My Activity → SMS Messages.
- The worker claims rows using row locks and SKIP LOCKED. Provider acceptance is not delivery. Signed status callbacks update delivery status; terminal statuses cannot regress.
- Failures/timeouts are held as failed without automatic retries. A crash after claiming may leave `sending`; operators must reconcile with Twilio before any resend. This avoids accidental duplicate messages but does not promise exactly-once external delivery.
- Advanced Opt-Out STOP records an idempotent consent withdrawal. START does not automatically restore local consent; recovery is still DEC05. HELP responses must be configured in Twilio. YES/NO replies do not change transactions in this integration.
- No SMS consent is inferred for seeded users. Don't activate real messaging in the recording sandbox. Plan a controlled test using consenting real phone owners before broad rollout.

## Verification

Tests use fake provider responses and never send live SMS. Cover encrypted/deduplicated outbox, consent suppression, acceptance, uncertain errors without resend, simulation isolation, Verify response handling, forged callbacks, duplicate STOP, and terminal delivery status ordering. Run the existing journey/SMS catalog regression suite as well.

References: https://www.twilio.com/docs/verify/quickstarts/ruby-rails , https://www.twilio.com/docs/messaging/api/message-resource , https://www.twilio.com/docs/usage/security , https://www.twilio.com/docs/messaging/tutorials/advanced-opt-out

Policy drafts, consent wording, publication blockers and campaign evidence checklist: `docs/SMS_POLICY_REVIEW.txt`. Prepared public routes are `/privacy.html`, `/sms-terms.html`, and `/sms-consent.html`; no policy publication or live SMS activation is implied.

## Activation progress — November 15, 2026

Console confirms FreeDME Notifications campaign Verified (ACCOUNT_NOTIFICATION). Advanced Opt-Out enabled; custom FreeDME STOP and HELP responses saved. START/UNSTOP/YES response explains carrier unblocking and asks users to contact inquiry@mobilityexchange.org to restore routine alerts, matching the app's persistent STOP gate. No automatic local reconsent implemented.

Messaging Service settings saved: inbound HTTP POST https://www.freedme.org/webhooks/twilio/incoming; delivery callback https://www.freedme.org/webhooks/twilio/status. Existing sender/encoding/validity settings preserved. These endpoints still require live-mode credentials before they can validate callbacks; service configuration is not proof of end-to-end delivery.

Local targeted tests passed: 16 runs, 188 assertions, zero failures/errors (Twilio integration, webhook signatures/STOP/status, SMS catalog). Local env files have no Twilio credentials. Awaiting AWS sign-in to securely configure hosted credentials and conduct user-authorized testing. No live SMS or OTP sent; no global provider activation performed. User supplied a consenting test number in conversation; it is not copied into this repository.

### Controlled hosted test — November 15, 2026
Auth Token entered by owner directly into hidden server prompt; .env.hosted remains mode 0600 and SMS_PROVIDER=simulated. Confirmed account API access, service callback URLs, and existing FreeDME Verify service VAf14b1c1941d4a22664949694a03127a4 (6 digits). Isolated compose run with SMS_PROVIDER=twilio used existing Rails TwilioClient to send one authorized notification and start one verification. Notification SM9eee02f6278caf6097e6fb7ed258433a returned delivered with no error. Verify request accepted; code completion not tested. No general web/worker live mode enabled. Awaiting recipient receipt/HELP confirmation. Signed callbacks currently require live mode and running web lacks newly saved credentials; account-level STOP and delivery callback integration remain pending. Do not treat this direct-client smoke test as full outbox/consent/OTP journey validation.

### Callback-only configuration
Set `TWILIO_WEBHOOKS_ENABLED=true` to accept authenticated Twilio callbacks while `SMS_PROVIDER=simulated`. This does not enable outbound notifications or real OTP sign-in. Signatures, Account SID, HTTPS public URL, form encoding and no-query-string checks remain mandatory. Recording mode rejects callbacks even with this flag. Targeted integration tests cover signed STOP suppression, invalid signatures, simulated defaults and recording isolation.

Callback-only mode deployed to Lightsail November 15, 2026. Rebuilt image and recreated web/worker with TWILIO_WEBHOOKS_ENABLED=true, SMS_PROVIDER=simulated. Public incoming endpoint accepted a signed non-mutating HELP probe (HTTP 200), rejected invalid signature (403). Local integration checks: 15 runs, 51 assertions, no failures/errors. Hosted test phone has no active AccountContact, so user was asked to register with optional consent before real STOP; account-level live STOP remains pending. Do not create consent on behalf of the user. Old controller retained on server as .rb.before_callback_mode for rollback.

### Real STOP callback verified — November 15, 2026
After user registration and explicit optional SMS consent, hosted check showed routine_sms_allowed=true and carrier_stopped=false. User sent STOP from the authorized test phone. Hosted Rails then confirmed routine_sms_allowed=false, carrier_stopped=true, stop_received=true, and a twilio-stop-prefixed callback idempotency key. Thus real signed inbound STOP reached Rails and its consent gate now suppresses routine messages for this account. User previously confirmed the HELP response. No post-STOP send attempted; opt-out remains intact. General outbound mode remains simulated. End-to-end delivery status persistence and successful Verify-code completion remain separate outstanding checks before full activation.

### Controlled START recovery test — 15 November 2026

The owner confirmed receiving the START/unblocked response and explicitly authorized restoration of optional SMS consent for their test account (mobile ending 0995), plus one test notification. Appended idempotent `reset` and `granted` consent events, preserving the earlier STOP record. Confirmed `allowed? = true` and `carrier_stopped? = false`.

Sent exactly one isolated test notification, recorded as `controlled_restart_test` with idempotency key `owner-authorized-start-test-20261115`. Twilio SID: `SMa92d0be3b1e70a39b335b41a400466f9`. The signed delivery callback persisted `delivery_status = delivered`, with no error. The running web service still reports live SMS disabled; general outbound delivery remains simulated. This was a manually authorized recovery, not automatic START re-consent. Verify code completion remains a separate outstanding test.

### End-to-end Verify test in progress — 15 November 2026

Owner authorized a real sign-in test. Temporary server Compose override `/tmp/freedme-verify-test.yaml` sets only web `SMS_PROVIDER=twilio`; worker was verified still `simulated`. Base `.env.hosted` unchanged. Website requested a real Verify code for the consenting owner's registered number and reached `/sign-in/verify`; awaiting owner entry and successful login. No OTP is recorded here. During this temporary mode web requests can queue real notification rows, but worker does not send them. Before broad activation inspect any queued rows. To revert after testing, recreate web using only base compose: `sudo docker compose --project-directory . --env-file .env.db -f deploy/lightsail/compose.yaml up -d --no-deps web` from `/home/ubuntu/freedme-rails-demo`.

### End-to-end Verify test passed — 15 November 2026

Owner entered the received code on the actual website and reached My Activity. Hosted database confirmed the latest challenge for the authorized test account had provider `twilio`, `consumed_at = 2026-11-15 09:04:36 -08:00`, and zero failed attempts. No OTP was read or recorded by the agent. Queued SMS count was zero. Recreated web with the base Compose configuration and verified `SMS_PROVIDER=simulated`; worker remained simulated throughout. Real Verify sign-in is now validated, along with earlier notification delivery, delivery callbacks, HELP, STOP, and manually authorized START recovery. General live activation has not been performed.
