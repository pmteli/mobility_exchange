# Verified fictional test users

Opt-in seed: `SEED_TEST_USERS=1 bin/rails db:seed` with `TEST_USERS_PASSWORD` set to a securely generated password. Allowed only in development/test or when DEPLOYMENT_STAGE=test and APP_HOST=test.mobilityexchange.org.

| Accounts | Community role | Staff access |
| --- | --- | --- |
| donor1@example.test through donor3@example.test | Donor | Public only |
| volunteer1@example.test through volunteer5@example.test | Volunteer | Volunteer permissions; approved profiles |
| recipient1@example.test through recipient10@example.test | Recipient | Public only |
| administrator1@example.test | None | Administrator |

All 19 accounts are active and email verified. Addresses are deliberately fictional. No verification emails are sent. Existing unrelated users are untouched. Seed-owned users are identified by stable IDs and auth_subject; collisions fail rather than adopting an unrelated account. Repeat runs preserve passwords and avoid duplicate profiles. Existing seed-owned accounts are restored to the declared active roles and verification state.

For AWS, generate the password on the instance and retain it in a permission-600 file outside the source tree. Supply it to the seeding process without putting it in command-line arguments or source. Use the recorded initial password for these accounts; a different password on repeat runs does not reset existing credentials.

Local validation: exact counts, verification state, approved volunteers, admin role, duplicate prevention, and password preservation passed (1 test, 10 assertions). Uploaded and executed on AWS on 2026-09-15. Exact counts and 19 active verified accounts confirmed; seed repeated successfully. Credentials are excluded from source and archives.
