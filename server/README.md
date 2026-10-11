# NAIWeaver Web Gateway

This backend serves the Flutter Web build, authenticates users, and proxies
NovelAI requests. The browser never receives the NovelAI token.

## Run

```bash
cd server
uv sync
NOVELAI_TOKEN_FILE="$HOME/.config/naiweaver/novelai_token.txt" \
NAIWEAVER_ADMIN_PASSWORD='local-test-admin' \
NAIWEAVER_ALLOWED_CLIENT_CIDRS='127.0.0.1/32,::1/128,192.168.31.0/24' \
uv run uvicorn app.main:app --host 0.0.0.0 --port 8000
```

For local tests without NovelAI:

```bash
NAIWEAVER_FAKE_NOVELAI=1 \
NAIWEAVER_ADMIN_PASSWORD='local-test-admin' \
NAIWEAVER_ALLOWED_CLIENT_CIDRS='127.0.0.1/32,::1/128,192.168.31.0/24' \
uv run uvicorn app.main:app --host 0.0.0.0 --port 8000
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

`--update` changes the role permissions and its default total point limits. It
does not erase points that have already been consumed. Use it deliberately.
`--green-points` overrides the selected role's permanent green-point total.

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

Browser cookies contain only a random session ID. Tokens stay in process
memory and are verified on receipt; normal requests check their validity
locally. Refreshes are serialized per session. Restarting the service requires
logging in again. Authentication and the one-second return screen are hosted
by only WebAuth. Local logout revokes the refresh token but does not end the
identity provider's session.

The browser stores no NovelAI token. The real token and production env file
should stay outside the repository:

- `~/.config/naiweaver/novelai_token.txt`
- `~/.config/naiweaver/env.production`

Deployment helpers are in `server/deploy/` and `server/scripts/`.

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
