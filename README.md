# Mobility Exchange — Rails MVC application

A working Rails 8.1 application for the core Mobility Exchange workflows, using the project's PostgreSQL 18 schema. This is application source code with a responsive interface, database-backed forms, authorization and tests. It is separate from the existing Sites prototype.

## Modern website views

The public and staff views now follow the project's newer navy, blue, and lime **Modern** website design, with the supplied logo, equipment illustrations, mobile layouts, and permission-aware operations sidebar. See [docs/DESIGN.md](docs/DESIGN.md) for the design mapping and browser checks.

## Run with Docker (local development)

Install Docker with Compose, open a terminal in this directory, then run:

```sh
docker compose build
docker compose up -d db
docker compose run --rm web bin/rails db:create db:migrate db:seed
docker compose run --rm web bin/rails mobility:demo
docker compose run --rm web bin/rails mobility:bootstrap_admin
docker compose up -d web worker
```

Open **http://localhost:3000**. The bootstrap task prompts for an administrator email and a password of at least 8 characters. Sign in with your email and password; no authenticator is required. There are no default login credentials. Sample data contains three clearly labeled items and no legal documents or usable sample accounts.

Compose is for local development: the web port binds to localhost, PostgreSQL has no host port, and email is written to a local volume. It does not deploy the app or send real email. To read development verification/reset messages:

```sh
docker compose exec web sh -c 'cat tmp/mail/*'
```

The worker processes queued account messages every five seconds. Stop the services with `docker compose down`; named volumes preserve data and signed files. Do not use `down -v` for a database containing records you need to retain.

## Run with a local Ruby installation

Use Ruby **3.4.10**, Bundler **2.6.9**, and PostgreSQL **18.x**. Ensure the PostgreSQL 18 client tools, especially `pg_dump` and `psql`, precede older versions on PATH.

```sh
bundle install
export DATABASE_URL='postgresql://localhost/mobility_exchange_development'
export TEST_DATABASE_URL='postgresql://localhost/mobility_exchange_test'
# Choose an installed Unicode TrueType font; Docker supplies DejaVu Sans.
export PDF_FONT='/path/to/DejaVuSans.ttf'
bin/rails db:create db:migrate db:seed
bin/rails mobility:demo
bin/rails mobility:bootstrap_admin
bin/rails server
```

Run `bin/notifications` in a second terminal for development email delivery, or use `bin/rails mobility:deliver_notifications` to process a batch. Development messages are saved in `tmp/mail`.

Use a **new database**. The first migration deliberately refuses to overwrite an existing `mobility_exchange` schema. It embeds the SQL from the earlier package, restores Rails' search path before migration bookkeeping, and preserves trigger-based workflow protection. A second migration adds encrypted local authentication credentials and revocable login sessions. Connecting an existing production database requires a reviewed upgrade migration rather than replaying the initial migration.

## What is implemented

- Public equipment catalog, category/search filters, pagination and details using a restricted database view.
- Registration, email verification and resend, password recovery, bcrypt passwords, encrypted cookies, server-side expiring sessions, logout, and an eight-character password minimum.
- Account dashboard scoped to the signed-in user's requests and donations.
- Donation submission, staff review, donor certification, drop-off booking and receipt of individual inventory units.
- Equipment requests, approval, reservation/cancellation, recipient waiver, pickup booking and distribution with signature evidence.
- Staff inventory creation/editing and controlled inspection, sanitization, repair and disposition transitions.
- Volunteer applications/approval, shifts, signups, cancellation, capacity and overlap protection.
- Appointment slot creation/cancellation with capacity and location checks.
- Editable plain-text public pages and inventory status CSV reports.
- Versioned legal text, immutable signed records, generated PDF/JSON evidence and access-controlled downloads.
- Models mapping all 48 original schema tables, plus two authentication tables and the public catalog view.
- An outbox worker for verification/reset email, audit records for core mutations, Docker files, CI configuration and integration tests.

See [docs/MVC.md](docs/MVC.md) for the code structure and [docs/FEATURES.md](docs/FEATURES.md) for the remaining requirements.

## Configure real content and legal documents

Replace sample content before real use. Locations and equipment types can be added with the operator task:

```sh
ACTOR_EMAIL='your-admin@example.org' LOCATION_NAME='Your center' TIMEZONE='America/Los_Angeles' bin/rails mobility:configure
ACTOR_EMAIL='your-admin@example.org' CATEGORY_ID='walkers' TYPE_NAME='Folding walker' bin/rails mobility:configure
```

The task also accepts `ADDRESS`, `CITY`, `REGION`, and `POSTAL_CODE` for locations. Database reference category IDs are `wheelchairs`, `walkers`, `bath`, `walking_aids`, and `other`.

No waiver or donor certification wording is invented or published by the app. Save your organization's approved exact text in a UTF-8 file, then publish each kind:

```sh
ACTOR_EMAIL='your-admin@example.org' KIND='recipient_waiver' VERSION='1' TITLE='Recipient waiver' TEXT_FILE='/path/to/approved-waiver.txt' bin/rails mobility:publish_legal
ACTOR_EMAIL='your-admin@example.org' KIND='donor_certification' VERSION='1' TITLE='Donor certification' TEXT_FILE='/path/to/approved-certification.txt' bin/rails mobility:publish_legal
```

For Docker, mount the text file read-only into a one-off web container and pass these environment values. Publishing appends a version and changes the active pointer; existing signed records remain immutable. The initial UI supports adults signing for themselves. Representative signing and drawn signatures require additional screens.

## Tests

Use a dedicated disposable test database. Tests insert unique records and intentionally do not use Rails' transaction-wrapped fixtures: business writes must start at SERIALIZABLE isolation. The test helper restores lookup data after Rails loads `structure.sql`.

```sh
RAILS_ENV=test bin/rails db:create db:migrate db:seed
bin/rails zeitwerk:check
bin/rails test
```

Inside Docker:

```sh
docker compose run --rm -e RAILS_ENV=test web bin/rails db:create db:migrate db:seed
docker compose run --rm -e RAILS_ENV=test web bin/rails test
```

See [VERIFICATION.md](VERIFICATION.md) for checks actually performed. Keep `Gemfile.lock`: JSON is explicitly constrained below version 3 because the installed Rails 8.1 release calls its parser with positional options.

## Production configuration

This package has not been deployed. Configure HTTPS, an application database role, encrypted persistent storage/backups, a durable private-files volume, and SMTP before operating it with real records. Production boot requires `SECRET_KEY_BASE`, `ENCRYPTION_PRIMARY_KEY`, `ENCRYPTION_DETERMINISTIC_KEY`, `ENCRYPTION_KEY_DERIVATION_SALT`, `APP_HOST`, `REDIS_URL`, and SMTP settings. Set `APP_PORT=443` and an appropriate `MAIL_FROM`. Generate encryption keys with `bin/rails db:encryption:init` and the cookie secret with `bin/rails secret`; keep them in your secret manager. `.env.example` is documentation and is not automatically loaded.

Run database migrations with an owner/migration role; give the runtime role only the table, sequence and function privileges it needs. The database schema revokes PUBLIC privileges but does not implement per-user row-level security; Rails enforces user authorization. `db:seed` reapplies the PUBLIC revocations after a structure-only restore. Review runtime grants for your deployment.

The notification worker delivers at least once; an SMTP acceptance followed by a crash can cause a duplicate. Monitor failed outbox records and use a separate worker process. Redis backs production throttling across processes. Development throttling is in-memory.

Private evidence is server-generated text/PDF, never arbitrary user uploads. The store uses opaque filenames, exclusive creation, restrictive permissions and digest verification. A failed database transaction may leave an unreferenced file; retain it until an operator confirms it has no database reference. File encryption, retention, backup recovery, malware scanning for future uploads, and deployment monitoring are operational work. Do not expose `storage/private` through your web server.

Authenticator codes are not required. Further role-management screens and broader PRD features are listed in the feature matrix. This is a tested core implementation, not a claim that the complete PRD or a production security review is finished.

## References

- [Rails MVC getting started guide](https://guides.rubyonrails.org/getting_started.html)
- [Rails migrations and SQL schema dumps](https://guides.rubyonrails.org/active_record_migrations.html)
- [Rails security guide](https://guides.rubyonrails.org/security.html)
- [PostgreSQL 18 transaction isolation](https://www.postgresql.org/docs/18/transaction-iso.html)

## Simplified registration and login

Passwords require 8–72 characters. Login uses email and password without an authenticator, including for administrators and existing accounts with saved MFA settings. Email verification still applies. New registrations must select one or more roles: Volunteer, Donor, and Recipient. These community roles are stored on the user and shown in My account. Volunteer registration does not grant staff processing privileges; the existing volunteer application and approval process remains available. Existing accounts retain their access and can have no community role selected. Run `bin/rails db:migrate` when upgrading.

## Connect email delivery

See [docs/EMAIL.md](docs/EMAIL.md) to enable SMTP for verification and password-reset messages, configure your sender, and run the delivery worker. Messages include branded HTML and plain text. Development defaults to local files until SMTP is explicitly enabled.

## Donor equipment photos

Donors may attach zero to three JPEG or PNG photos when submitting a donation (5 MB per file). Photos are decoded, resized to fit 1600 by 1600 pixels, stripped of metadata and stored privately as JPEG. The owner and staff with intake.review can view them. They are not automatically published in the public catalog. Existing files and intake_item_files tables are used, so no database migration is needed. Install ImageMagick (`convert`) for native development; Docker and CI install it automatically. The private storage volume must persist across deployments.

### Editing a profile

Signed-in users can choose **My account → Edit profile** to update their name,
phone, and mailing address. Contact details are also updated on their linked donor
and recipient records. Role and account-status changes are not permitted here.

Changing email requires the current password and a confirmation link sent to the
new address. The existing email remains active until confirmation. Links expire
in 24 hours; confirmation signs out existing sessions. Enter the current password
again to resend a pending link, or restore the existing email to cancel it.
The normal notification worker and configured mail delivery method handle these
messages; file delivery captures them locally instead of sending SMTP mail.

Deploy this feature with `bin/rails db:migrate` before restarting the web and worker
services. Validation: 28 tests / 281 assertions plus `bin/rails zeitwerk:check`.
