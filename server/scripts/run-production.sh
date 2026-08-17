#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="/Users/redcontritio/Projects/NAIWeaver"
ENV_FILE="${NAIWEAVER_ENV_FILE:-$HOME/.config/naiweaver/env.production}"

if [[ ! -r "$ENV_FILE" ]]; then
  echo "Missing NAIWeaver env file: $ENV_FILE" >&2
  exit 2
fi

set -a
# shellcheck source=/dev/null
source "$ENV_FILE"
set +a

cd "$PROJECT_DIR"
exec "$PROJECT_DIR/server/.venv/bin/uvicorn" app.main:app \
  --app-dir "$PROJECT_DIR/server" \
  --host "${NAIWEAVER_HOST:-127.0.0.1}" \
  --port "${NAIWEAVER_PORT:-62279}" \
  --no-proxy-headers
