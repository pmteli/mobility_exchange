# Local Docker deployment

The Rails framework uses the existing PostgreSQL 18 container `mobility-exchange-rails-db-1` on the external Docker network `mobility-exchange-rails_default`.

- Website: http://localhost:3001
- Compose project: `freedme-framework`
- Databases: `freedme_framework_development` and `freedme_framework_test`
- Login: `freedme_framework` (not a superuser; owns only the new application databases)
- Credentials: `.env.docker`, ignored by Git, excluded from Docker builds and readable only by the local owner. Do not commit or share it.

The existing application on port 3000 and its `mobility_exchange_development` database are unchanged. The PostgreSQL port is not published to the host; Rails connects over the existing Docker network. The database volume remains managed by the original Compose project. Start that project's database container before starting this app.

Run commands from `freedme_app`:

```sh
docker compose -f compose.local.yml build
docker compose -f compose.local.yml run --rm web bin/rails db:migrate db:seed
docker compose -f compose.local.yml up -d
docker compose -f compose.local.yml logs --tail=50 web
```

Test using the separate test database:

```sh
docker compose -f compose.local.yml run --rm -e RAILS_ENV=test web bin/rails db:migrate
docker compose -f compose.local.yml run --rm web bin/rails test
```

Stop only this framework:

```sh
docker compose -f compose.local.yml down
```

The container runs an image snapshot; rebuild after changing local source. It runs in development mode and binds only to host loopback. This is not a production deployment. Local simulated OTP and database-backed journeys are enabled as described in the application README; real SMS/evidence and production authentication remain disabled. A separate local journey_worker processes deadlines every 30 seconds. The database initially has reference categories but no published equipment.

The schema uses irreversible initial migrations. Do not reset an existing database to update it; add forward migrations. This local login intentionally cannot create other databases, so use the provisioned databases rather than `db:create`, `db:reset` or test database purge tasks.
