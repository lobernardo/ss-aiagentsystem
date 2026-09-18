# ScanSolo Deployment (Docker Compose)

This document describes the deployment topology for the ScanSolo Chatwoot
platform and the operational procedures around it: process topology,
storage, reverse proxy/TLS, health checks, volumes, migrations, restart
policy, backup/restore, environment variables, log rotation, and rollback.

It is documentation only. No task in this phase performs an actual
production deploy, DNS cutover, or provider activation (RF-94) — those
remain behind the human-approval gates in `PLAN.md` Phase 18 (T82–T90).

Related documents:
- `docs/architecture/ADR-001-chatwoot-scansolo-platform.md` — architecture
  decision and target topology diagram.
- `docs/architecture/SCANSOLO_UPSTREAM_RISK.md` — high-merge-conflict-risk
  customizations against `chatwoot/chatwoot` upstream.
- `.env.example` — full list of supported environment variables.

## Topology

| Component | Compose service | Image / build | Notes |
|---|---|---|---|
| Web (Rails) | `rails` | `docker/dockerfiles/rails.Dockerfile` (dev) / `chatwoot/chatwoot:latest` (prod) | Serves the API and dashboard on port 3000. |
| Background jobs | `sidekiq` | same image as `rails` | Runs `bundle exec sidekiq -C config/sidekiq.yml`; owns all ScanSolo async jobs (cadence, AI turns, Make callbacks). |
| Database | `postgres` | `pgvector/pgvector:pg16` | PostgreSQL with the `pgvector` extension, required by the ScanSolo knowledge/RAG tables (RF-28). |
| Cache / queue | `redis` | `redis:alpine` | Sidekiq queue backend and Rails cache. |
| Object storage | `minio` (self-hosted) or an external S3-compatible provider | `minio/minio:latest` | See "Object storage" below. |
| Reverse proxy / TLS | `reverse-proxy` | `caddy:2-alpine` | Terminates TLS in front of `rails`; automatic Let's Encrypt via `SCANSOLO_DOMAIN`. |
| Backup | `backup` (one-off) | `postgres:16-alpine` | Never started by `up`; run explicitly (see "Backup / restore"). |

The additive service definitions, health checks, restart policies, and log
rotation described here live in `docker-compose.scansolo.yaml`. It never
replaces the existing `docker-compose.yaml` (local dev) or
`docker-compose.production.yaml` (single-node production baseline) — it
layers on top of either.

Staging/production usage:

```sh
docker compose -f docker-compose.yaml -f docker-compose.production.yaml \
  -f docker-compose.scansolo.yaml up -d
```

Config lint only (used by this phase's test, never a real deploy):

```sh
docker compose -f docker-compose.yaml -f docker-compose.scansolo.yaml config
```

## Object storage (S3-compatible)

Chatwoot's Active Storage already ships an `s3_compatible` service definition
(`config/storage.yml`) driven by `STORAGE_ACCESS_KEY_ID`,
`STORAGE_SECRET_ACCESS_KEY`, `STORAGE_REGION`, `STORAGE_BUCKET_NAME`,
`STORAGE_ENDPOINT`, and `STORAGE_FORCE_PATH_STYLE`. Two supported options:

1. **Managed S3-compatible provider** (e.g. AWS S3, DigitalOcean Spaces):
   set `ACTIVE_STORAGE_SERVICE=s3_compatible` and the `STORAGE_*` variables
   above to the provider's credentials/endpoint. No additional compose
   service is required.
2. **Self-hosted MinIO**: start the `minio` service (profile
   `self-hosted-storage`) from `docker-compose.scansolo.yaml`, and point the
   same `STORAGE_*` variables at it (`STORAGE_ENDPOINT=http://minio:9000`,
   `STORAGE_FORCE_PATH_STYLE=true`).

Provider account creation/activation is out of scope for this phase — see
gate T88 (RF-100).

## Reverse proxy / TLS

The `reverse-proxy` service (profile `reverse-proxy`) runs Caddy in front of
`rails`, terminating TLS and issuing/renewing Let's Encrypt certificates
automatically for the hostname in `SCANSOLO_DOMAIN`. Certificate state
persists in the `scansolo_caddy_data`/`scansolo_caddy_config` volumes so
renewals survive container restarts.

DNS cutover for the production hostname (`scansolo.com.br`) is a separate,
gated action — see T85 (RF-100). Nothing in this phase points a real domain
at any host.

## Health checks

`docker-compose.scansolo.yaml` adds a `healthcheck` to every long-running
service:

- `rails`: HTTP spider check against `http://localhost:3000`.
- `sidekiq`: `sidekiqmon processes` returns at least one running process.
- `postgres`: `pg_isready`.
- `redis`: `redis-cli ping` (authenticated with `REDIS_PASSWORD`).
- `minio`: MinIO's own `/minio/health/live` endpoint.
- `reverse-proxy`: HTTP spider check on port 80.

## Persistent volumes

| Volume | Owner service | Contents |
|---|---|---|
| `postgres_data` / `postgres` | `postgres` | Database files. |
| `redis_data` / `redis` | `redis` | Redis persistence (AOF/RDB). |
| `storage_data` | `rails` | Local Active Storage fallback (dev/local only). |
| `scansolo_storage` | `minio` | Self-hosted object storage data (only when the `minio` profile is used). |
| `scansolo_caddy_data` / `scansolo_caddy_config` | `reverse-proxy` | TLS certificates and Caddy state. |
| `scansolo_backups` | `backup` | Local landing zone for `pg_dump` archives before they are shipped off-host. |

## Migrations

Migrations run as a one-off command against the `rails` image, before
bringing up (or as part of rolling) the new `rails`/`sidekiq` containers:

```sh
docker compose -f docker-compose.yaml -f docker-compose.production.yaml \
  -f docker-compose.scansolo.yaml run --rm rails bundle exec rails db:migrate
```

Every ScanSolo migration is additive-only (`create_table` / additive
`add_column`, never `remove_column`/`change_column` on a pre-existing
Community table — enforced by `spec/db/scansolo_migrations_spec.rb`, T79),
so a migration run is always forward-compatible with the previous release
still running during a rolling deploy. Actually executing `db:migrate`
against a production database is gated separately — see T84 (RF-100).

## Restart policy

`rails`, `sidekiq`, `postgres`, `redis`, `minio`, and `reverse-proxy` all use
`restart: always`, so the Docker daemon restarts them on crash or host
reboot. The `backup` service uses `restart: "no"` — it is a one-off job, never
a long-running process.

## Backup / restore

Backups are triggered manually (or from an external host cron job), never
automatically, using the `backup` profile:

```sh
docker compose -f docker-compose.yaml -f docker-compose.production.yaml \
  -f docker-compose.scansolo.yaml --profile backup run --rm backup
```

This produces a gzip-compressed `pg_dump` archive under the
`scansolo_backups` volume, named `chatwoot-<timestamp>.sql.gz`. Ship these
archives off-host (e.g. to the same S3-compatible bucket configured for
object storage) on a schedule appropriate to the deployment's RPO.

Restore procedure (run against a stopped or freshly-provisioned `postgres`
volume):

```sh
gunzip -c chatwoot-<timestamp>.sql.gz | \
  docker compose -f docker-compose.yaml -f docker-compose.production.yaml \
    -f docker-compose.scansolo.yaml exec -T postgres psql -U postgres -d chatwoot
```

Object storage (`minio` volume, or the external S3-compatible bucket) is
restored independently, per the provider's own backup/versioning tooling.

## Environment variables

All environment variables are documented in `.env.example`, loaded via
`env_file: .env` on every service in `docker-compose.yaml` /
`docker-compose.production.yaml`. ScanSolo introduces no new
deployment-specific variables beyond the existing `STORAGE_*` set
(already documented in `.env.example` and `config/storage.yml`) and the two
additive ones used by `docker-compose.scansolo.yaml`:

- `SCANSOLO_DOMAIN` — hostname the `reverse-proxy` service issues a TLS
  certificate for (defaults to `localhost` when unset, which yields a
  self-signed/local-only certificate — never used for a real deploy).
- `STORAGE_ACCESS_KEY_ID` / `STORAGE_SECRET_ACCESS_KEY` — reused, when the
  `minio` self-hosted storage profile is active, as the MinIO root
  credentials so a single credential pair configures both the storage
  service and the Rails client pointed at it.

## Log rotation / observability

`docker-compose.scansolo.yaml` applies Docker's `json-file` log driver with
`max-size: 10m` and `max-file: 5` to every service, bounding on-disk log
growth without an external log shipper. Existing Rails-level log
configuration (`RAILS_LOG_TO_STDOUT`, `LOG_LEVEL`, `LOG_SIZE` in
`.env.example`) is unaffected and continues to write to stdout, which Docker
captures under this same rotation policy.

## Rollback

Because every ScanSolo migration is additive-only, rolling back application
code does not require a down-migration:

1. Stop the current `rails`/`sidekiq` containers.
2. Re-deploy the previous image tag/commit for `rails` and `sidekiq`
   (`docker compose ... up -d --no-deps rails sidekiq` with the prior image
   reference).
3. Leave the database schema as-is — additive columns/tables unused by the
   rolled-back code are simply ignored by it.
4. If a specific ScanSolo feature must be disabled without a code rollback,
   toggle the per-account `scansolo_enabled` flag instead of rolling back the
   whole deploy.
5. If the incident involves data corruption rather than a bad deploy,
   restore from the most recent backup per "Backup / restore" above.

No rollback step here performs a real deploy, DNS change, or provider
action — this document only describes the procedure for when a human
operator executes it, per RF-94/RF-100.
