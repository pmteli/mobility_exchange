# Verification performed

Verified locally on September 12, 2026 using Ruby 3.4.10, Rails 8.1.3.1 and PostgreSQL 18.6 (Postgres.app), against an isolated temporary database.

- Fresh PostgreSQL migrations executed successfully, including the local authentication extension.
- Rails SQL structure dump/load and reference seed restoration exercised by the test runner.
- `zeitwerk:check` passed; all 51 concrete models map to existing tables/views.
- **16 integration/service tests, 148 assertions: zero failures, errors or skips.**
- Full request journey: submit, approve, reserve, sign waiver, authorize PDF access, book pickup and record distribution.
- Full donation journey: submit, sign certification, approve, book drop-off and receive exactly one unit per declared quantity.
- Public/private data separation, ownership enforcement, staff authorization, registration role tampering, unverified-login rejection, admin MFA and replay prevention tested.
- Password reset revokes sessions and consumes the token; email verification/resend and test-mode notification delivery tested.
- Invalid inventory transitions, serializable-write enforcement, shift capacity and invalid schedule submissions tested.
- Staff pages, public request/donation forms, report CSV and HTML escaping rendered through Rails integration requests.
- Optional sample seed ran twice; exactly three sample inventory items remain.
- Compose YAML parsed successfully and contains database, web and notification-worker services.

The Docker image and GitHub Actions workflow were supplied but not executed on this machine. Live SMTP, production hosting and a formal security/accessibility review were not performed. The Modern design update was visually checked in the browser at 320px, 390px, 768px, and 1280px on the pages listed in docs/DESIGN.md; mobile/tablet width checks showed no document overflow. Catalog filtering and mobile workspace navigation were exercised.

No real user email was sent. Test signatures and generated files are excluded from the source archive. The archive includes only application source, schema, tests, configuration and documentation.

## Modern design regression check

Rails loading and the full existing integration suite passed after the view recreation: 16 tests, 148 assertions, zero failures/errors/skips. A separate preview database contained fictional sample data only.

## Simplified login and registration

18 tests, 169 assertions, zero failures/errors/skips. Verified eight-character password validation, administrator login without OTP even with a saved secret, all three role combinations, and rejection of missing/unsupported roles. Browser confirmed the updated sign-in and registration forms. Migration applied to local test and preview databases.

## Recipient signup option

Added Recipient as a selectable community role. All seven nonempty combinations persist successfully without staff permissions. Test and preview database constraints migrated. Full suite: 18 tests, 179 assertions, no failures/errors/skips.

## Gmail SMTP integration

20 tests, 193 assertions, no failures/errors/skips. Gmail STARTTLS defaults, TLS alternative, missing credential errors, and HTML/plain-text email rendering verified. No external email sent; live Gmail delivery remains untested pending App Password configuration.
