# Test account cleanup

`clear_test_users.sql` is a manual maintenance operation, never part of startup,
seeding, or a migration. It deletes all accounts (including administrators),
credentials, sessions, role assignments, requests, donation records, bookings,
messages, notifications, and activity/audit history from the named test database.

Inventory, equipment photos, categories/types, locations/hours, schedules,
website pages, legal templates, organization settings, and permission definitions
are preserved. Creator references are cleared; inventory is classified as legacy
when its source donation/purchase is removed. The nullable-attribution migration
must be applied first. Normal application writes still supply the current actor.

Before execution, stop web and worker; take and verify a private PostgreSQL dump
and private-files/test-mail volume backups. Rehearse on a restored database named
`mobility_user_cleanup_rehearsal`. The script uses one transaction, temporarily
suppresses triggers in that transaction, verifies every foreign key and preserved
table count, and restores normal trigger behavior at transaction end. Any SQL
error aborts the operation. It requires the database maintenance superuser.

After successful cleanup, remove orphaned private files (retain any files still
referenced by inventory), clear test mail and the dedicated Redis database 0,
and restart the services. Verify zero accounts/activity and preserved inventory,
locations, pages, and shifts; check public pages and registration. Do not run
seeds, which would recreate accounts. Keep backup files restricted to the server
operator; they contain the removed personal data. External email providers and
payment processor records are outside this database cleanup.

The September 18, 2026 cleanup preserved 25 inventory items, 115 scheduled shifts,
6 locations, 25 location-hours records, and 3 pages. Recovery dumps and file
archives are stored on the test server under
`/home/ubuntu/backups/user-cleanup-20260918/` (private directory). No admin account
is recreated automatically after cleanup.
