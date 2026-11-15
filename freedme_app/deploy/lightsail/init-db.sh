#!/bin/bash
set -eu
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" --set=app_password="$APP_DB_PASSWORD" <<'SQL'
CREATE ROLE freedme_demo LOGIN PASSWORD :'app_password' NOSUPERUSER NOCREATEDB NOCREATEROLE;
ALTER DATABASE freedme_hosted_demo OWNER TO freedme_demo;
GRANT ALL ON SCHEMA public TO freedme_demo;
SQL
