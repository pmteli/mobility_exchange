# AWS testing deployment — $25 monthly budget

Prepared for a single Lightsail Linux public-IPv4 instance: 2 GB RAM, 2 vCPUs, 60 GB disk, $12/month list price. Suggested region: us-west-2 (Oregon). Use an Ubuntu LTS OS-only image. Recheck the console price before creation. No AWS resources have been created by these files.

Reserve up to $5/month for modest snapshot usage, leaving $8 for taxes and contingencies. Snapshot and excess-transfer charges vary; $25 is a target, not a hard billing cap. Do not add RDS, a load balancer, NAT gateway, or managed Redis to this test setup. Configure billing alerts at $20 and $25. Stopping an instance does not eliminate its allocated-resource charges; delete unneeded resources after testing.

Rails, PostgreSQL 18, Redis, Caddy, and the mail worker share one server. This is for light testing with synthetic data, with no high availability. The database owner is also the application role in this isolated test stack. Database and Redis ports are not published. Only HTTP/HTTPS are public; restrict SSH to the operator's IP. Consider 2 GB swap for image builds; monitor memory/disk usage. Building and running this Docker stack on AWS has not yet been verified.

## Prepare the server

1. Create the $12 Linux IPv4 Lightsail instance and attach a Lightsail static IP. Keep it attached to avoid idle-IP charges.
2. Install Docker Engine and the Compose plugin using Docker's official Ubuntu instructions: https://docs.docker.com/engine/install/ubuntu/ . Enable Docker at boot.
3. Upload this application source to the server, excluding local secrets, logs, tmp files, and local storage. Do not copy live databases from a laptop.
4. In GoDaddy DNS add an A record named `test` pointing to the static IP, TTL 600 if available. Check for conflicting records at that name. Keep the root, www, MX and email TXT records unchanged. Do not add AAAA unless IPv6 is configured.
5. Open Lightsail TCP 80 and 443. Restrict TCP 22 to your IP. No public 3000, 5432, or 6379.

## Configure and start

Run commands from this directory (`deploy/lightsail`) on the server. They affect only the named `mobility-test` Compose project.

```sh
cp .env.example .env
chmod 600 .env
```

Edit `.env` locally on the server. Set all empty values. Generate separate hex values for each secret using `openssl rand -hex 32` (use 64 for SECRET_KEY_BASE). Keep these encryption keys stable across deployments. SMTP_PASSWORD must be a Google App Password for the configured account. Do not commit or share `.env`. This Compose file loads it for both application processes. Gmail delivery requires account policy to permit App Passwords; see ../../docs/EMAIL.md.

```sh
docker compose config --quiet
docker compose build web
docker compose up -d db redis
docker compose run --rm web bin/rails db:prepare
docker compose run --rm web bin/rails mobility:bootstrap_admin
docker compose up -d web worker proxy
docker compose ps
```

The admin task prompts for email and password. No default credentials are provided. Sample inventory seeding is disabled in production mode; add fictional inventory through the admin workflow. Caddy issues and renews HTTPS certificates after DNS resolves and ports 80/443 are reachable. Visit https://test.mobilityexchange.org . The noindex header discourages indexing but does not make the site private.

## Verify and maintain

- Verify HTTPS, login, signup roles, one verification email to your own address, password reset, catalog, and a fictional donation/request.
- Check `docker compose logs --tail=100 web worker proxy`. Avoid sharing logs containing personal data or tokens.
- Store periodic database dumps and private files off-server; also preserve the encryption keys securely. For a consistent backup, pause web and worker writes first. A database-only backup does not include signed documents in the private_files volume.
- Keep a small number of Lightsail snapshots and review billed snapshot storage. Test restoration before relying on backups.
- For updates, back up first, stop web and worker, rebuild, run `docker compose run --rm web bin/rails db:migrate`, then `docker compose up -d`. Keep the previous source and backups for recovery. Some migrations are irreversible.
- Never run `docker compose down -v` unless deliberately deleting the test database and private files.

## References

- AWS bundle prices: https://docs.aws.amazon.com/lightsail/latest/userguide/amazon-lightsail-bundles.html
- Snapshot/transfer prices: https://aws.amazon.com/lightsail/pricing/
- Caddy HTTPS: https://caddyserver.com/docs/automatic-https

## Deployed test site (2026-09-15)

Live URL: https://test.mobilityexchange.org
Static IP: 34.212.115.157. Server folder: `/home/ubuntu/mobility-exchange`.

In Lightsail **Connect using SSH**, create your first administrator interactively:

```sh
cd /home/ubuntu/mobility-exchange/deploy/lightsail
sudo docker compose run --rm web bin/rails mobility:bootstrap_admin
```

Enter your email and chosen password when prompted. No administrator has been created automatically.

Configure Gmail privately from the same folder:

```sh
python3 configure-gmail.py
sudo docker compose up -d --force-recreate web worker
```

Until then, this test deployment explicitly uses local email capture. Verification links are saved privately in the `test_mail` Docker volume; they are not sent to inboxes. The normal production default remains SMTP. Changing to SMTP does not resend already captured messages; use Resend verification or a new password-reset request afterward. Do not share the contents of captured emails because they contain account tokens.

Build, PostgreSQL 18.6 migration, HTTPS, public routes, signup options, and writable mail storage verified. The local regression suite passed 20 tests and 193 assertions. No full end-to-end live email or signed-document journey has been tested on AWS yet. Inventory starts empty. Backups and billing alerts are not configured.
