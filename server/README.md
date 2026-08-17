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

Production login is WebAuthn-only. Create or update a user from the backend
virtualenv, then issue a one-time enrollment link:

```bash
cd server
.venv/bin/python -m app.cli user create admin --role admin --update
.venv/bin/python -m app.cli webauthn bind admin --ttl 30m --base-url https://nai.recoco.xyz
```

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
NovelAI token. Image generation is queued globally, limited to one active task
per user, and forced to `n_samples = 1`.
