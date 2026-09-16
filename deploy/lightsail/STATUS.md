# AWS testing deployment status

Updated 2026-09-15. Account 054772657474; instance mobility-exchange-test in us-west-2a, Ubuntu 24.04, $12/month 2 GB plan.

- Running; static IP mobility-exchange-test-ip attached: 34.212.115.157.
- Inbound HTTPS TCP 443 added for IPv4. Existing HTTP and SSH rules remain.
- Temporary deployment SSH key added with explicit user approval; removed from authorized_keys after verification.
- Docker Engine and Compose installed; 2 GB swap configured.
- Source uploaded to /home/ubuntu/mobility-exchange; image built and Rails/worker/proxy running.
- Server-only application/encryption/database secrets generated in deploy/lightsail/.env (mode 600).
- Test mail capture enabled (DEPLOYMENT_STAGE=test, MAIL_DELIVERY_METHOD=file). Gmail credential still pending.
- GoDaddy A record test -> 34.212.115.157 requested; DNS and public HTTPS verified.
- Local regression: 20 tests, 193 assertions, no failures/errors.

Public homepage, CSS, signup, login and catalog: HTTP 200. PostgreSQL 18.6 and private mail-directory writes verified. Gmail sending and initial admin creation pending user credential entry; no admin created.

2026-09-15: Test-user seed uploaded, image rebuilt, seed run twice, and web/worker restarted. Verified 3 donors, 5 approved volunteers, 10 recipients, 1 administrator; all 19 active and email verified. Temporary SSH key removed again after seeding.


2026-09-15: Applied migration 20260915000000_seed_test_equipment. Verified 25 sample items available across four categories; repeat seed preserved inventory. Catalog and six illustration URLs passed HTTPS checks. Temporary deployment key removed.
