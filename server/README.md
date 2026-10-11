# NAIWeaver Web Gateway

This backend serves the Flutter Web build, authenticates users, and proxies
NovelAI requests. The browser never receives the NovelAI token.

## Run

```bash
cd server
uv sync
NOVELAI_TOKEN_FILE="$HOME/.config/naiweaver/novelai_token.txt" \
NAIWEAVER_ADMIN_PASSWORD='local-test-admin' \
uv run uvicorn app.main:app --host 127.0.0.1 --port 8000
```

For local tests without NovelAI:

```bash
NAIWEAVER_FAKE_NOVELAI=1 \
NAIWEAVER_ADMIN_PASSWORD='local-test-admin' \
uv run uvicorn app.main:app --host 127.0.0.1 --port 8000
```

## Build Web

```bash
flutter build web --release --output server/static/web
```

Open `http://127.0.0.1:8000/` or the Mac mini LAN address.

## Local Test Accounts

In development mode the backend bootstraps these local accounts when they do not
exist. Production disables password login and test account bootstrap by default.

- `admin / local-test-admin`
- `free_user / free-test-pass`
- `paid_user / paid-test-pass`

Each is created with its role's defaults (see below). When
`NAIWEAVER_ADMIN_PASSWORD` is set, every start resets the existing `admin`
password and re-applies the admin role's permissions; point totals are left
alone.

## Production Auth

Production login uses only WebAuth through OIDC Authorization Code + PKCE.
Passkeys are managed by the identity provider; this service no longer exposes
its own WebAuthn endpoints. Existing users, history, quotas and local permissions
remain in NAIWeaver.

```bash
NAIWEAVER_PUBLIC_BASE_URL=https://nai.example.com
NAIWEAVER_AUTH_ISSUER=https://auth.example.com
NAIWEAVER_AUTH_CLIENT_ID=naiweaver
NAIWEAVER_AUTH_CLIENT_SECRET_FILE=/path/to/client.secret
NAIWEAVER_AUTH_SUBJECT_MAP='{"immutable-provider-user-id":1}'
NAIWEAVER_AUTH_KEY_CACHE_MINUTES=10080
```

### User and point administration

Run all administrative commands from `server/`. They operate on the production
database selected by the production environment file when the LaunchAgent is
running.

```bash
cd /Users/redcontritio/Projects/NAIWeaver/server
```

Create a user, or apply one of the predefined roles to an existing user:

```bash
# Roles: free, paid, admin
.venv/bin/python -m app.cli user create alice --role free
.venv/bin/python -m app.cli user create alice --role paid --update
.venv/bin/python -m app.cli user create agent_test --role free --green-points 10000
```

`--update` changes only what is passed. `--role` re-applies that role's
permissions and green discount but never its point totals, so earlier grants
and consumed points are kept; `--green-points` sets the permanent green-point
total. Without `--update`, an existing user is an error. A new user is created
with all of the role's defaults, including point totals, and `--green-points`
overrides the green total.

The admin API (`POST /api/admin/users`) takes the same `role`; fields left out
take the role's values and explicit fields override them. Administrators always
get a `100%` green discount, on creation and when promoted by `PATCH`.
`role: "admin"` together with `is_admin: false` is a contradiction and is
rejected with 400 `invalid_parameters` (`field: "is_admin"`).

`agent_test` is the canonical account for live browser, smoke, and end-to-end
tests against the deployed service. Keep credentials and WebAuthn enrollment
links outside the repository. Isolated unit tests must continue using their
local fixture users so role, migration, and multi-user behavior remain
deterministic and never mutate production data.

Enable or disable a user:

```bash
.venv/bin/python -m app.cli user disable alice
.venv/bin/python -m app.cli user enable alice
```

Set a green-point discount for ordinary free images. At `100%`, the green
charge is zero, so generation is unlimited. Admin users are created with a
`100%` green discount:

```bash
.venv/bin/python -m app.cli user green-discount alice --percent 100
.venv/bin/python -m app.cli user green-discount alice --percent 25
```

Issue or inspect points:

```bash
# Show permanent remaining and total balances.
.venv/bin/python -m app.cli user points show alice

# Add permanent red points. This raises the total allocation; it never resets
# a balance or schedules recurring grants.
.venv/bin/python -m app.cli user points grant alice --red 1000
```

Green represents ordinary free generation. `green_point_discount` is an
integer percentage from `0` to `100`; green costs are charged after that
discount, and `100` means no green points are consumed. `green_point_limit`
and all red-point fields are permanent: they do not reset by day, month, or
time period.

Register the exact callback `https://nai.example.com/auth/callback` with only
WebAuth and grant the appropriate group access to the client. Map immutable
provider user IDs to existing local numeric user IDs using
`NAIWEAVER_AUTH_SUBJECT_MAP`; no username-based matching or account creation
happens at login. Unmapped users retain their data but cannot sign in.

Browser cookies contain only a random session ID. Sessions, with their refresh
tokens (encrypted with a key derived from the client secret, so rotating the
secret signs everyone out; the database file is created with mode 0600), are stored in the gateway's SQLite database under a SHA-256 digest of
that ID, so they survive restarts. Access tokens are verified on receipt and
normal requests check their validity locally. Refreshes are serialized per
session; an identity provider outage keeps the session (`auth_unavailable`),
while a rejected refresh or an unmapped subject ends it. Unauthenticated page
loads are redirected to `/auth/login?return_to=...` so login returns to the
original page. Authentication and the one-second return screen are hosted
by only WebAuth. Local logout revokes the refresh token but does not end the
identity provider's session.

The browser stores no NovelAI token. The real token and production env file
should stay outside the repository:

- `~/.config/naiweaver/novelai_token.txt`
- `~/.config/naiweaver/env.production`

Deployment helpers are in `server/deploy/` and `server/scripts/`.

### Database schema and the one-off upgrade

`app/db.py` holds one final `SCHEMA` and `PRAGMA user_version` (currently `1`).
The gateway never migrates on startup:

- a new, empty database is created with the final schema;
- `user_version` equal to the code's version starts normally;
- anything else, including the production database from before this release
  (`user_version` 0), makes the service and every `app.cli` command stop with an
  error that points here.

Upgrading the production database from `user_version` 0 is a one-off step done
with `python -m app.cli db upgrade`. It only needs SQLite (no NovelAI, no
identity provider). It first checks the column structure of every table and
exits without touching anything if it differs from the expected version-0
structure. The upgrade runs in a single transaction (foreign keys off while
tables are rebuilt; `PRAGMA foreign_key_check` and a comparison with the final
schema before commit), so a failure leaves the database as it was. It

- adds `request_audit_logs.request_body_expired_at` and creates
  `only_webauth_sessions`, `generation_item_errors`, `billing_anomalies` and
  `tool_reservations`;
- rebuilds `generation_tasks` and `generation_submission_tasks` without their
  retired columns (`cost`, `anlas_before/after`, `paid_points_charged`, the
  red/green `reserved_`/`released_` columns, and all point columns on
  submissions), copying every row and keeping ids, idempotency keys and
  indexes; `consumed_red_points` is filled from `paid_points_charged` where an
  older paid row only had the latter;
- drops `daily_quotas`, `quota_usage`, `admin_config`, `schema_migrations`,
  `legacy_quota_snapshots` and the three `webauthn_*` tables (the dry run lists
  how many rows each holds);
- rebuilds `users.green_points_reserved` / `red_points_reserved` the way
  `recompute_reserved_points` does at startup.

Steps (run from `server/` with the production environment loaded; `--db PATH`
selects another file than the configured one):

1. Stop the service so nothing writes to the database:
   `launchctl bootout gui/$(id -u)/com.redcontritio.naiweaver`
2. Back up. Either let the tool do it in step 5 (`--backup-to`), or make and
   check your own copy, for example `sqlite3 "$DB" ".backup '$DB.pre-v1'"`
   and `sqlite3 "$DB.pre-v1" "PRAGMA integrity_check"`.
3. Dry run (the default). The database file is opened read-only and the whole
   upgrade is rehearsed on an in-memory copy:
   `.venv/bin/python -m app.cli db upgrade`
4. Check the output: rows copied per rebuilt table, the dropped columns and
   tables with their row counts, which users' reserved counters change, and
   the final "checks passed" line. A structure mismatch is an error here.
5. Apply. Exactly one backup option is required:
   `.venv/bin/python -m app.cli db upgrade --apply --backup-to ~/backups/gateway-v0.sqlite3`
   writes a backup with the SQLite backup API, checks the copy
   (`integrity_check`, row counts) and then upgrades; or
   `.venv/bin/python -m app.cli db upgrade --apply --backup-verified` confirms
   that you made and checked a backup in step 2.
6. Start the new version:
   `launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.redcontritio.naiweaver.plist`
   (or `kickstart`), check `stderr.log`, then smoke-test with `agent_test`.
7. If the upgrade fails, it rolled back and nothing changed: fix the cause or
   keep running the old release. If the new version misbehaves, stop it and put
   the backup back: delete `$DB-wal` and `$DB-shm` (so no stale write-ahead
   log is replayed over the restored file), then
   `cp ~/backups/gateway-v0.sqlite3 "$DB"` and start the previous release.

Once production is at version 1, `app/db_upgrade.py`, its CLI command and
`tests/test_db_upgrade.py` can be deleted.

### macOS Production Service

The production service is installed as a user LaunchAgent:

- plist: `~/Library/LaunchAgents/com.redcontritio.naiweaver.plist`
- runner: `server/scripts/run-production.sh`
- env: `~/.config/naiweaver/env.production`
- logs: `~/.config/naiweaver/stdout.log` and `~/.config/naiweaver/stderr.log`
- local listen: `127.0.0.1:62279`

Restart it after changing env or backend code:

```bash
launchctl kickstart -k gui/$(id -u)/com.redcontritio.naiweaver
```

The public route uses frp `https2http`:

- frpc config: `~/.config/frp/frpc.toml`
- snippet: `server/deploy/frpc.naiweaver.toml`
- public URL: `https://nai.recoco.xyz`
- certificate: `~/.config/naiweaver/certs/nai.recoco.xyz.{crt,key}`

`server/deploy/tencent_dns_a.py` is a small stdlib-only DNSPod helper used to
set `nai.recoco.xyz A 118.89.50.15` from the Tencent credentials already saved
by acme.sh.

## Proxy Model

The Flutter app keeps the original NAIWeaver UI and request builders. In Web
mode, NovelAI endpoints are mapped to backend routes:

- image host: `/api/nai/image/...`
- api host: `/api/nai/api/...`
- text host: `/api/nai/text/...`

The backend strips any browser `Authorization` value and injects the local
NovelAI token. Image generation is submitted only through
`/api/generation-tasks`, queued globally, forced to `n_samples = 1`, and each
user may hold up to 20 unfinished image tasks by default. Configure that
capacity with `NAIWEAVER_MAX_QUEUED_IMAGE_TASKS_PER_USER`.

Pricing, submission, errors and history payloads follow
`docs/GATEWAY_CONTRACT.md`. Every NovelAI image call (queued generations and
paid tools) runs through one serialized upstream lane, red-point work first.
Paid tools are quoted at a configurable cap, reserved before the call and
settled at the measured Anlas cost:

```bash
NAIWEAVER_TOOL_CAP_UPSCALE=10
NAIWEAVER_TOOL_CAP_AUGMENT=80
NAIWEAVER_TOOL_CAP_ENCODE_VIBE=2
# How long free-eligible work is priced in red points after NovelAI charged
# Anlas for a free image (see the free allowance in the contract).
NAIWEAVER_FREE_ALLOWANCE_COOLDOWN_SECONDS=1800
```

Settlements that disagree with their quote are recorded in the
`billing_anomalies` table.

## Audit retention

Every proxied request and generation submission is audited. The request body
of an accepted request is stored under `NAIWEAVER_AUDIT_DIR`; a rejected
generation submission records metadata only, never the body.

Body files older than `NAIWEAVER_AUDIT_RETENTION_DAYS` (default `30`; `0`
keeps them forever) are deleted at startup and once a day. The audit rows stay
in the database, lose their body path and are marked
`request_body_expired_at`; `GET /api/admin/audit/{id}/body` then answers 404
with an "expired" message, and `GET /api/admin/audit` reports
`request_body_expired: true`.

## Module layout

`app.main:app` only assembles the application (middleware, error handlers,
lifespan, routers). See "Gateway server modules" in `ARCHITECTURE.md`.
