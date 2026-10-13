# ScanSolo Deployment (Docker Compose)

This document is the production deploy runbook for the ScanSolo Chatwoot
platform: topology, the ordered deploy procedure with rollback, OpenAI key
rotation and the pre-cutover setup rule.

Production is always, and only:

```sh
docker compose -f docker-compose.production.yaml -f docker-compose.scansolo.yaml
```

The dev compose file is never part of a production command. TLS, certificates,
the public domain and the host reverse proxy are managed outside this
repository; no step here touches them. The `reverse-proxy` and
`self-hosted-storage` overlay profiles are never activated.

Related documents:
- `docs/runbooks/PRODUCTION_CUTOVER.md` — cutover checklist (webhook owner, kill switch).
- `docs/runbooks/SCANSOLO_GO_LIVE_TEST.md` — controlled go-live test.
- `.env.example` — every variable the production compose and ScanSolo read.

## Topology

| Component | Compose service | Image / build | Notes |
|---|---|---|---|
| Web (Rails) | `rails` | `scansolo-chatwoot:${SCANSOLO_IMAGE_TAG}` built from `docker/Dockerfile` | API and dashboard on `127.0.0.1:3000`. |
| Background jobs | `sidekiq` | same image as `rails` | Owns every ScanSolo async job (AI turns, cadences, Make callbacks). |
| Database | `postgres` | `pgvector/pgvector:0.8.1-pg16` | PostgreSQL with `pgvector` (knowledge/RAG tables). |
| Cache / queue | `redis` | `redis:8.2.1-alpine` | Sidekiq backend and Rails cache, password from `REDIS_PASSWORD`. |
| Backup | `backup` (profile `backup`) | `postgres:16.10-alpine` | One-off `pg_dump`; never started by `up`. |
| Proposal PDF (local mode) | `gotenberg` | `gotenberg/gotenberg:8.37.0` | Converts the rendered `.docx` proposal to PDF. Internal network only, **no published port**; Rails/Sidekiq reach it at `SCANSOLO_GOTENBERG_URL=http://gotenberg:3000`. |

Image tags must equal what the VPS runs; step 1 checks it (HG-08). Every port
is published on `127.0.0.1` only (`gotenberg` publishes none).

Local proposal mode: `SCANSOLO_GOTENBERG_URL` set in `.env` turns it on, with
precedence over the Make credentials — the proposal PDF is rendered from the
account's `.docx` template and converted by `gotenberg`, and Make is never
called. Empty or absent keeps the Make flow. Removing the variable and
restarting Rails and Sidekiq is the rollback of the mode, with no redeploy. Health checks, `restart: always` and
`json-file` log rotation (`10m` × 5) come from `docker-compose.scansolo.yaml`.

Persistent volumes: `postgres_data` (database), `redis_data` (Redis),
`storage_data` (Active Storage local files), `scansolo_backups` (`pg_dump`
archives — ship them off-host).

## Database name

Production Rails uses `chatwoot_production` (Chatwoot's default when `POSTGRES_DATABASE` is unset). The `chatwoot` database created by
`POSTGRES_DB` in `docker-compose.production.yaml` is not used by the application. Backups and restores always target
`chatwoot_production` (override with `POSTGRES_DATABASE` in `.env` if the VPS ever uses another name).

## Deploy procedure

Run every step from the deploy directory on the VPS, in order, in the same
shell. Stop at the first failing step and go to step 9.

### Step 1 — Diff the VPS compose and .env names against Git

```sh
git fetch origin
git diff HEAD origin/main -- docker-compose.production.yaml docker-compose.scansolo.yaml
git status --short docker-compose.production.yaml docker-compose.scansolo.yaml
diff <(grep -oE '^[A-Z0-9_]+=' .env | sort -u) <(grep -oE '^[A-Z0-9_]+=' .env.example | sort -u)
docker ps --format '{{.Names}} {{.Image}}'
export PREVIOUS_SCANSOLO_IMAGE_TAG=$(docker inspect --format '{{.Config.Image}}' "$(docker compose -f docker-compose.production.yaml -f docker-compose.scansolo.yaml ps -q rails)" | cut -d: -f2)
echo "$PREVIOUS_SCANSOLO_IMAGE_TAG"
```

Passes when there is no local edit to the compose files, every name missing
from `.env` is understood (and filled if required; for the local proposal mode
`SCANSOLO_GOTENBERG_URL=http://gotenberg:3000`), the running `postgres` and
`redis` images equal the tags in `docker-compose.production.yaml`, and the
previous image tag is recorded for rollback.

### Step 2 — Back up the database and check the dump size

```sh
docker compose -f docker-compose.production.yaml -f docker-compose.scansolo.yaml \
  --profile backup run --rm backup
docker compose -f docker-compose.production.yaml -f docker-compose.scansolo.yaml \
  --profile backup run --rm --no-deps --entrypoint sh backup -c 'ls -lh /backups | tail -n 3'
```

Passes when the newest `chatwoot_production-<timestamp>.sql.gz` exists, is not empty and
its size is in line with the previous dump. Record its file name for step 9.

### Step 3 — Build the image with GIT_SHA and a new SCANSOLO_IMAGE_TAG

```sh
git checkout <release-ref>   # the validated release branch/commit; origin/main holds only planning docs today
export GIT_SHA=$(git rev-parse HEAD)
export SCANSOLO_IMAGE_TAG=$(date +%Y%m%d%H%M)-$(git rev-parse --short HEAD)
docker compose -f docker-compose.production.yaml -f docker-compose.scansolo.yaml build rails
```

The build fails when `GIT_SHA` is empty. Never reuse a previous tag.

### Step 4 — Run migrations

```sh
docker compose -f docker-compose.production.yaml -f docker-compose.scansolo.yaml \
  run --rm rails bundle exec rails db:migrate
```

### Step 5 — Load the cadence definitions

```sh
docker compose -f docker-compose.production.yaml -f docker-compose.scansolo.yaml \
  run --rm rails bundle exec rails scansolo:load_cadence_definitions
```

Passes when the 4 active definitions are printed. The task is idempotent.

### Step 6 — Restart Rails

Start (or update) `gotenberg` first, so the local proposal mode has its
converter before Rails and Sidekiq read `SCANSOLO_GOTENBERG_URL`:

```sh
docker compose -f docker-compose.production.yaml -f docker-compose.scansolo.yaml up -d --no-deps gotenberg
docker compose -f docker-compose.production.yaml -f docker-compose.scansolo.yaml ps gotenberg
docker compose -f docker-compose.production.yaml -f docker-compose.scansolo.yaml up -d --no-deps rails
```

`gotenberg` must report `healthy` before Rails is restarted.

### Step 7 — Restart Sidekiq

```sh
docker compose -f docker-compose.production.yaml -f docker-compose.scansolo.yaml up -d --no-deps sidekiq
```

### Step 8 — Run the smoke check

In local mode, first upload the proposal template v3 (`.docx`, approved
beforehand, never versioned in Git) as an administrator in the dashboard:
ScanSolo → Propostas → template card → select the file → Enviar. The card must
show the new file name and hash. Without an active template the smoke reports
`FAIL proposal_integration` and every generation fails with
`template_unavailable` (reprocessable after the upload).

```sh
docker compose -f docker-compose.production.yaml -f docker-compose.scansolo.yaml \
  exec rails bundle exec rails "scansolo:smoke[<account_id>]"
```

Passes when every line is `PASS` (in local mode `PASS proposal_integration`
only with the uploaded template) and the task prints `ScanSolo smoke passed`
(non-zero exit on any `FAIL`). Only then process a real commercial reply.

### Step 9 — Rollback

Application rollback to the previous image tag:

```sh
export SCANSOLO_IMAGE_TAG=$PREVIOUS_SCANSOLO_IMAGE_TAG
docker compose -f docker-compose.production.yaml -f docker-compose.scansolo.yaml up -d --no-deps rails sidekiq
```

Database restore from the step 2 dump (only when data must be reverted; stops
Rails and Sidekiq first):

```sh
docker compose -f docker-compose.production.yaml -f docker-compose.scansolo.yaml stop rails sidekiq
docker compose -f docker-compose.production.yaml -f docker-compose.scansolo.yaml \
  --profile backup run --rm --no-deps --entrypoint sh backup -c \
  'dropdb -h postgres -U postgres chatwoot_production && createdb -h postgres -U postgres chatwoot_production && gunzip -c /backups/chatwoot_production-<timestamp>.sql.gz | psql -h postgres -U postgres -d chatwoot_production'
docker compose -f docker-compose.production.yaml -f docker-compose.scansolo.yaml up -d --no-deps rails sidekiq
```

To stop ScanSolo outbound without a rollback, turn the account's
`scansolo_enabled` flag off (kill switch).

## OpenAI key rotation

The OpenAI key is the `CAPTAIN_OPEN_AI_API_KEY` InstallationConfig (Super
Admin → Settings). After saving or rotating it, restart Rails and Sidekiq so
both processes pick up the new key:

```sh
docker compose -f docker-compose.production.yaml -f docker-compose.scansolo.yaml restart rails sidekiq
```

Then run the step 8 smoke check.

## Pre-cutover setup with an empty inbox allowlist

`scansolo_enabled` is the single ScanSolo kill switch (D-21): turning it off
also hides the ScanSolo UI and API. Pre-cutover setup (agent config,
knowledge, templates) is therefore done with the flag **on** and an **empty
inbox allowlist** in the published agent config, which keeps ScanSolo outbound
at zero. Fill the allowlist only at cutover.
