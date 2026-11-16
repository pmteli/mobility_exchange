FreeDME hosted Rails review demo (FR003/FR018, NFR003/004/007/008)

This is a review deployment, not approval to launch a production exchange.
RAILS_ENV=production enables compiled assets, HTTPS and generic error pages.
FREEDME_HOSTED_DEMO=true explicitly enables fictional journey accounts and
simulated SMS, and refuses any database except freedme_hosted_demo.
AWS Rekognition and Textract are real, region us-west-2. Do not upload personal
documents to this shared test environment. Identity images expire after 7 days;
the journey worker performs the existing purge and deadline processing.

Hosting:
- demo.freedme.org: public Rails entry pages; Rails sign-in/role checks protect member actions.
- /test-data (including format/path variants): reviewer HTTP Basic authentication protects the shared simulated SMS/OTP inbox.
- demo.freedme.org/journeys/: existing public narrated recordings.
- www.freedme.org: Coming Soon homepage and static policies; remaining paths proxy to the same isolated Rails pilot.
- www /test-data variants redirect to the password-protected demo inbox.
- Hosted SMS_LINK_BASE_URL=https://www.freedme.org; SMS remains simulated.
- PostgreSQL 18: private Docker network; persistent database volume.
- Application role is not a PostgreSQL superuser.
- Uploads: shared persistent Docker volume for web and worker.
- No local database dump, real uploads, master.key or .env files in the package.
- Server-only .env.hosted contains generated database/application secrets and
  the explicitly authorized freedme AWS credentials. Never commit it.

Deploy from the app root on the server:
  docker compose --project-directory . --env-file .env.db -f deploy/lightsail/compose.yaml build
  docker compose --project-directory . --env-file .env.db -f deploy/lightsail/compose.yaml up -d db
  docker compose --project-directory . --env-file .env.db -f deploy/lightsail/compose.yaml run --rm web bin/rails db:migrate db:seed
  docker compose --project-directory . --env-file .env.db -f deploy/lightsail/compose.yaml run --rm -e SEED_JOURNEYS=1 web bin/rails db:seed
  docker compose --project-directory . --env-file .env.db -f deploy/lightsail/compose.yaml up -d web worker

Seed fictional accounts only once; do not reset the database on deployment.
Validate Rails and PostgreSQL health before updating/reloading Caddy.
Keep the previous Caddyfile and static site outside the active route for rollback.
Rollback routing by restoring the archived static files into site (preserve
journeys and coming-soon), restoring that Caddyfile and reloading Caddy; do not delete
Rails volumes. Back up the PostgreSQL database before future schema changes.

Privacy lifecycle upgrade (14 November 2026, prepared; not yet deployed)
- Preserve existing database/uploads, reviewer authentication, journeys and server-only secrets. Do not seed/reset during this upgrade.
- Web and worker require the new persistent privacy_backups volume at /var/lib/freedme/backups. Generate a separate PRIVACY_BACKUP_KEY on the server if absent; never print it or copy local keys.
- Take a protected pre-migration backup, apply db:migrate, start web/worker and verify privacy:backup and worker health. Include any pre-migration backup in the deletion inventory.
- Verify administrator-only backup controls; do not grant administrator access to every moderator.
- Permanent erasure remains disabled unless separately run by the owner with reviewed shared content and logs. Production role separation is still required before enabling that maintenance workflow.
- Publish policy/consent HTML and footer links to the public coming-soon site after hosted verification; review effective-date/draft wording at publication. Live SMS remains disabled.

CURRENT OVERRIDE — 15 November 2026 protected prelaunch testing:
www serves the Rails homepage and app behind existing reviewer Basic authentication.
Only static policies/consent/assets and signed Twilio webhook routes are public.
demo redirects to www, including recordings; recordings/test-data require the gate.
Hosted web and worker explicitly use real Twilio SMS after owner approval.
Local/recording environments remain simulated. Existing hosted database is preserved.
Do not reseed/reset or treat the prelaunch switch as public-launch authorization.
