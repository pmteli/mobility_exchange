# FreeDME Rails application framework

Rails 8.1 MVC foundation for the FreeDME website, backed by the PostgreSQL 18 v0.2 schema. The existing interactive prototype remains separate and unchanged. This is a development foundation, not a production-ready implementation of all journeys.

## Local Docker instance

Use [the Docker deployment guide](deploy/LOCAL_DOCKER.md) for the existing local PostgreSQL container. FreeDME runs separately at http://localhost:3001 with dedicated development and test databases.

## Run locally

Use Ruby 3.4 (developed with 3.4.10), Bundler, and PostgreSQL 18. Use a dedicated application database and PostgreSQL 18 command-line tools (`psql`, `pg_dump`) on PATH. Use a **new empty database**; the initial migration refuses to overwrite an existing `freedme` schema.

```sh
cd freedme_app
bundle install
export DATABASE_URL=postgresql://localhost/freedme_development
export TEST_DATABASE_URL=postgresql://localhost/freedme_test
bin/rails db:create db:migrate
bin/rails db:seed
bin/rails db:test:prepare
bin/rails test
bin/rails server
```

Visit http://localhost:3000. Standard PostgreSQL environment variables (`PGHOST`, `PGPORT`, `PGUSER`, `PGPASSWORD`) can also be used. If your shell defaults to an older Ruby, activate Ruby 3.4 first (`rvm use 3.4.10` on this workstation). Never point tests at a live database. `.env.example` documents variables; it is not loaded automatically.

## MVC structure

- **Models:** `app/models` explicitly maps all 53 schema tables, including composite primary keys. Single-column foreign keys are mapped as associations, with key composite associations for exchanges. PostgreSQL remains authoritative for constraints, triggers, immutable history and UUIDv7 defaults. Other composite foreign keys remain database-enforced; add associations as their services are implemented. Models are persistence mappings, not authorized workflow APIs.
- **Controllers:** public pages and equipment search/detail; separate donor, recipient and moderator namespaces. `AuthenticatedController` deliberately denies all private access until verified server-side sessions and role/participant authorization exist. There are no public write endpoints.
- **Views:** accessible server-rendered ERB, shared responsive layout, equipment filters and detail, informational pages, and private dashboard templates. No client-side simulator state is imported.
- **Queries:** `EquipmentCatalog` searches only the database-approved `available_listing_cards` view, with bound values, literal wildcard escaping, deterministic ordering and bounded pages. No private contact or identity fields are queried by public controllers.
- **Services:** OTP, SMS and evidence-verifier interfaces raise `Integrations::NotConfigured`. No messages are sent and no evidence is collected.
- **Jobs:** `HandoffFollowupJob` invokes the idempotent seven-day database function using server time. No automatic scheduler is enabled; configure a durable queue and schedule before use.
- **Database:** initial migration embeds the existing v0.2 SQL and is deliberately irreversible. SQL schema dumps preserve PostgreSQL-specific behavior; use `db/structure.sql`, not `schema.rb`.

The migration and idempotent `db:seed` task seed seven categories but no approved equipment configurations, users, evidence or listings. An empty equipment page is expected. Pilot gates remain disabled. Do not bypass publication screening to populate a demo.

## Requirement traceability

| Foundation | Requirement references | Remaining work |
| --- | --- | --- |
| Public equipment catalog/projection | FR006–008, FR033, FR035 | Approved geography/configuration, sanitized photos, full browse UX |
| Account and participant model boundaries | FR003, FR021–022, FR026, FR036 | Real OTP/session issuance, recovery, authorization, encrypted storage and consent |
| Listings and revisions | FR004–006, FR012, FR020, FR034, FR038 | Transactional submission/edit/review services and donor forms |
| Exchanges and handoff persistence | FR010–011, FR023–025, FR044–045 | Authorized transitions, locking/idempotency, notices/outbox and deadline jobs |
| Questions and notifications | FR009, FR018, FR027, FR041 | Participant-scoped Q&A, encryption, delivery/retry/STOP processing |
| Moderator task job | FR043 | Durable worker schedule, role authorization and staff UI |

Baseline: PRS v0.10 and subsequent explicit user decisions as represented by PostgreSQL schema v0.2. DEC01–DEC06 and unresolved operational policy choices are not silently resolved here. No launch or deployment is implied.

## Before enabling account journeys

Implement verified session authentication and participant/role policies before removing the private-controller gate. Moderator access additionally requires staff authentication policy. Build authorized transaction services that update state, audit events and notification outbox atomically; model `save!` alone is not a complete journey. Configure key management, restricted object storage, document processing, retention and provider adapters before collecting evidence or contact details. Add a least-privilege database runtime role rather than running the website as its migration owner.

Finish production host restrictions, secret management, durable jobs, monitoring and recovery checks. Review all open policy decisions and add full workflow/concurrency/security tests. The existing SQL regression suite in `../database/freedme_pg18_v0_2/tests.sql` complements the Rails tests.

Framework reference: [Rails Getting Started](https://guides.rubyonrails.org/getting_started.html).

## Local journey seed data (2026-10-27)

FR003/FR026: five fictional active accounts with simulated verified mobile contacts.
Donors: Nina Shah (+1 510-555-0101), David Chen (+1 510-555-0102).
Recipients: Maya Patel (+1 510-555-0103), Alex Rivera (+1 510-555-0104).
Moderator: Sam Morgan (+1 510-555-0105). No real staff credentials or MFA are fabricated.
All numbers are fictional. Contacts are encrypted with a development-derived key and
marked `fictional-seed-v1`; they are not usable production credentials.

FR004/FR006: each donor has a walker, cane, shower chair, crutches and manual wheelchair.
Four gifts and one loan per donor, all pending review. No photo, recall clearance,
policy approval, identity evidence or actual reservation is fabricated. Pilot gates
remain disabled. The seed loader uses stable IDs and preserves existing test progress.

Run only against the isolated local Rails database:

```sh
docker compose -f compose.local.yml build
docker compose -f compose.local.yml run --rm web bin/rails db:migrate
docker compose -f compose.local.yml run --rm -e SEED_JOURNEYS=1 web bin/rails db:seed
docker compose -f compose.local.yml up -d
```

Open http://localhost:3001/test-data for the personas, inventory and simulated SMS inbox.
The ordinary `db:seed` command still loads reference data only. Journey seeding refuses
production. FR018: `Integrations::SmsGateway` records template-rendered messages in
`simulated_sms_messages` in development/test; production fails closed. No network calls,
Twilio credentials or outbound message jobs are created. Seeds log five welcome messages
and ten listing acknowledgements, once each. New calls can supply an idempotency key.

These fixtures prepare backend journey testing; they do not implement live sign-in,
moderation, requests or handoffs. Existing `/design-preview` flows remain presentation
samples and are not wired to these database records. The local test-data page is read-only.

## Working local journeys (2026-10-27 — supersedes the unconnected-workflow notes above)

Sign in at http://localhost:3001/sign-in using a seeded mobile number; read the
six-digit code in http://localhost:3001/test-data, then verify it. No text is sent.
All five personas can sign in. New members register with display name, approximate
location and mobile, and are created only after their simulated code succeeds.
Moderator access is reserved for the seeded staff role; registration cannot choose it.
Staff OTP is a **local authentication simulation**, not the production email/password/MFA flow.

My Activity is now database-backed, with equipment, transactions, grouped private Q&A,
and an account-specific simulated SMS inbox. A moderator sees review and follow-up queues.
The old `/design-preview` screens remain independent visual snapshots.

Recommended walkthrough:
1. Sign in as Sam (510-555-0105); review and publish a sample listing.
2. Sign out, sign in as Maya (510-555-0103), browse it, ask a question or request it.
3. Choose a simulated identity result and consent. Failure creates no donor-visible request.
4. Sign in as Nina (510-555-0101) for her equipment: answer questions, approve with a
   public pickup location/time, decline, or mark unavailable.
5. As Maya, accept or counter the pickup proposal. As Nina, accept or counter again.
6. Either participant can confirm the physical handoff once. For a loan, only the donor
   confirms return; the donor must affirm possession before making it available again.

FR003/026: encrypted cookie sessions expire after eight hours; CSRF protection remains
on. OTPs have keyed digests, ten-minute expiry, three attempts, one-minute resend spacing
and a five-code/hour limit. These are **local test settings**, not decisions for production.
`SECRET_KEY_BASE` is stored in the ignored `.env.docker` to persist sessions/contact encryption
across container restarts. Do not rotate it without a contact/key migration. The one-time
`journeys:refresh_fixture_contacts` task re-keys only the five known fictional seed phones.

FR004/006/038: submission and immutable edit revisions queue for moderator review.
Local publication records synthetic policy/recall/photo screening using a placeholder;
no actual product inspection or recall verification is claimed. FR021/022: identity input
uses fabricated fields and no uploaded documents. A request transaction creates simulated
evidence, disclosure consent and allocation together. Only the donor sees the name/ZIP
through the audited database function; address remains private. Local requests enable
synthetic privacy/loan controls in this isolated database. **Do not migrate this development
data or synthetic approvals to production.** DEC01–DEC06 and real pilot approvals stay open.

FR010/011/023–025: listing locks serialize competing allocations; database uniqueness and
transition guards remain active. Donor approval gives a 24-hour offer, recipient acceptance
or counterproposal creates a reservation; proposals are immutable and revision checked.
Duplicate/stale approvals, handoffs and returns fail safely. Cancellation/consent revocation
ends at handoff. Expired retries hide the earlier entry without deleting history.

FR018/041: all SMS remains in `simulated_sms_messages`, committed with the underlying action.
No Twilio API is called. Q&A is encrypted, participant-scoped and grouped by equipment.
Real provider retries, delivery callbacks and consent recovery remain production work.
FR024/043: `journey_worker` checks 48-hour requests, 24-hour offers and seven-day reserved
follow-up tasks every 30 seconds; activity requests also run a catch-up check. Manually run
`bin/rails journeys:tick` if needed. Moderator follow-up resolutions do not infer a handoff.
The worker and web service are started with `docker compose -f compose.local.yml up -d`.

All workflow/authentication simulation is disabled outside development/test. Real identity verification, production staff MFA and SMS delivery remain unimplemented.
The global test-data/OTP inbox is local-only; it is intentionally an inspection tool and
must never be deployed as a production OTP channel.

Test database lifecycle is explicit: migrate it before `bin/rails test`; automatic destructive
schema refresh is disabled. Test cases use transactional rollback. Existing app port 3000
and Lightsail are untouched.

Validation: 24 tests / 772 assertions passed on 27 October 2026. Browser smoke test: Sam signed in, published Nina’s sample walker; Maya signed in and submitted a request with simulated identity/consent. The pending request is intentionally retained in development for the next donor step.


### Equipment photos (FR004–005, FR008, FR034–035)

The live `/donate` and edit forms accept 1–5 JPEG/PNG photos, at most 5 MiB and
25 megapixels each. These are local implementation limits consistent with the existing
schema; they do not close open production policy decisions. Preview and remove selected
files before submitting; edit a listing to keep, remove or replace its photos. Failed
submissions preserve text and existing images; browser security requires reselecting new files.

`EquipmentMedia::Photos` decodes images using the OS-maintained Pillow package in the local
Docker image, rejects invalid/animated/oversized images, applies EXIF orientation and creates
fresh JPEG pixel data at up to 2400px per side. Embedded metadata is discarded. Original
uploads are transient request files and are never published. Sanitized photos are sent to Amazon Rekognition when screening is enabled.

Sanitized files live outside `public` in the `freedme-framework_equipment_photos` Docker
volume. Back up this volume together with PostgreSQL. Rebuilding containers preserves it;
`docker compose down -v` deletes it. Test media uses a separate ephemeral directory.
`/equipment-photos/:id` checks authorization on every read and disables browser caching.
Pending/rejected photos are restricted to owner/moderator. Public access requires an approved
photo on an eligible published listing. Authorized transaction recipients can see approved
photos for their exchange; editing hides the prior published photos while re-review is pending.

Edits create immutable photo references on a new revision; removing a photo hides it from
the new revision but preserves historical review records. Moderator approval carries the
actual sanitized photos forward and records content-review time. Moderators must inspect
photos for private information and inappropriate content. The Rekognition integration below provides automated content screening when configured; equipment safety and recall screening remain local simulations. Legacy fictional seed listings may still
use their explicit placeholder until edited. Design-preview screens remain fictional/read-only;
real uploads are on `/donate`. Gallery arrows, thumbnails, keyboard navigation and swipe
reuse the prototype's styles and behavior.


### Amazon Rekognition integration (FR005/FR006/FR035)

Each image selection sends the sanitized photo to an authenticated same-origin preflight
endpoint, then to `DetectModerationLabels` as bytes (no S3 bucket needed). The browser shows
Checking, Passed, Needs moderator review, Replace photo, or Retry. Files and form text remain
in the browser on check failure. A second server-side check at submission prevents bypass;
publication also checks the current screening policy. Exact sanitized bytes are hashed and
results cached per account/policy in `freedme.photo_screenings` to avoid repeat paid calls.
Only digest, labels, model version, decision and timestamps are stored by the screening table;
preflight temporary files are removed. The regular listing upload stores sanitized media.

**Local setup verified on 28 October 2026:** the dedicated `freedme` AWS profile successfully
called Rekognition in us-west-2 from both the CLI and Rails container. A fictional sample
passed screening (model 7.0), and a repeated Rails check reused the cached result with one
API attempt. Local screening is enabled using `compose.rekognition.yml`. The user approved `reject_explicit` for the local pilot: explicit adult content at
90% confidence or higher is rejected; other flags go to moderator review. Tests use AWS SDK stub responses.
Failures block unchecked submissions/publication; existing fictional seed previews remain available.

1. Set up a dedicated AWS identity/profile with `config/rekognition-iam-policy.json` (only
   DetectModerationLabels in us-west-2). No S3 or face-recognition permissions are needed.
2. Configure profile `freedme` outside chat using `aws configure --profile freedme` (or your
   organization's temporary credential workflow). Never commit or paste keys into chat.
3. Set `REKOGNITION_ENABLED=true` in ignored `.env.docker`. Set `REKOGNITION_POLICY` to
   `review_only` (default, all flags go to review) or `reject_explicit` (explicit adult category
   at confidence >=90 is rejected; other flags >=60 go to review). These are pilot rules,
   not a validated production moderation policy. A policy change invalidates cached decisions.
4. Launch with `docker compose -f compose.local.yml -f compose.rekognition.yml up -d web`.
   For another profile prefix the command with `FREEDME_AWS_PROFILE=profile-name`.
   Alternatively supply AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY and optional AWS_SESSION_TOKEN
   via the ignored `.env.docker` and use only `compose.local.yml`. Prefer temporary credentials.
5. Check an ordinary non-sensitive test equipment image on `/donate`. Confirm a Passed or
   Needs review status, then confirm a second selection of identical content uses the cache.

Errors/timeouts/invalid credentials are never passes; retry is available with a one-minute
cooldown. Paid API attempts are capped at 30 per account per hour (conservative on retries).
SDK automatic retries are disabled, with 3s connection and 10s read timeout. Browser checks
run sequentially and time out at 35s. Set AWS budget alerts separately; the per-account limit
is not an account-wide dollar cap. Moderators see labels/confidence in Listing Reviews.
No original photos, image bytes, keys, or raw AWS error responses are logged by this service.

Run migrations for development and test before tests. No production integration is activated
by these local changes. Provider references:
https://docs.aws.amazon.com/sdk-for-ruby/v3/api/Aws/Rekognition/Client.html
https://docs.aws.amazon.com/rekognition/latest/dg/moderation-api.html

### Equipment-photo classification (FR005/FR006/FR035)

`REKOGNITION_EQUIPMENT_ENABLED=true` adds DetectLabels after adult-content screening.
The AWS identity needs the updated policy in config/rekognition-iam-policy.json.
This adds a second billable analysis per uncached image (adult rejections skip it).
Recognized aids at >=80% confidence continue through moderation. Wheelchairs, walkers,
canes, crutches, shower chairs and commodes have conservative label/alias mappings.
Under the user's revised strict policy, any image without an allowed equipment label
at >=80% confidence is rejected immediately, including close-ups, generic chairs, wheels,
unknown equipment, and absent labels. Other is not a recognition bypass. Donors must remove
the image and upload a clear equipment photo; it cannot proceed to moderator review.
Recognized equipment still undergoes adult/content screening and listing approval.
This does not verify the selected category or equipment safety and may reject valid
photos the general-purpose model cannot recognize. API failures remain retryable and
block submission/publication, rather than being treated as image rejections.
Policy version v3-strict-equipment invalidates cached decisions from the prior review rule.
Both AWS permissions are active in us-west-2.

### Material dropdowns

Rails native single-select markup is progressively enhanced to official Material Web
2.5.0 outlined selects, bundled locally with esbuild. Native controls remain the fallback
if JavaScript does not load. Labels, names, initial selections, disabled options, required
validation, form association and conditional loan fields are preserved. Newly inserted
dialogs are enhanced too. No runtime CDN or CSP relaxation is required.
Run `npm ci` and `npm run build:selects` using a supported Node.js version after changing
app/javascript/material_selects.js. Commit the lockfile and generated asset with changes.
Reference: https://github.com/material-components/material-web/blob/main/docs/components/select.md

### SMS translations (FR003 / FR018)

`config/locales/en.yml` is the runtime source of all 18 simulated SMS messages,
under `en.sms`. Dynamic values use Rails placeholders such as `%{display_name}`,
`%{item_title}`, `%{verified_name}`, `%{town}`, `%{code}` and `%{expiry_minutes}`.
`Integrations::SmsGateway` renders the current I18n locale and persists the rendered
message. Missing keys or variables raise before recording a message. Existing
SMS history is unchanged. Database notification templates and their migrations
remain historical reference data, not the runtime wording source. SMS delivery
remains simulated; adding translations does not enable an external provider.

Example: `Support.notify(account, "listing_submitted", { item_title: revision.title })`.
Add future SMS templates here and route all delivery through the gateway.
