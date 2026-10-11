#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${NAIWEAVER_ENV_FILE:-$HOME/.config/naiweaver/env.production}"

if [[ ! -r "$ENV_FILE" ]]; then
  echo "Missing NAIWeaver env file: $ENV_FILE" >&2
  exit 2
fi

set -a
# shellcheck source=/dev/null
source "$ENV_FILE"
set +a

# Production runs from a release checkout pinned to one commit, never from
# the development tree; the data directory is configured separately.
PROJECT_DIR="${NAIWEAVER_PROJECT_DIR:?Set NAIWEAVER_PROJECT_DIR to the release checkout in $ENV_FILE}"
if [[ -z "${NAIWEAVER_DATA_DIR:-}" ]]; then
  echo "Set NAIWEAVER_DATA_DIR in $ENV_FILE so the release checkout uses the existing data" >&2
  exit 2
fi

cd "$PROJECT_DIR"
exec "$PROJECT_DIR/server/.venv/bin/uvicorn" app.main:app \
  --app-dir "$PROJECT_DIR/server" \
  --host "${NAIWEAVER_HOST:-127.0.0.1}" \
  --port "${NAIWEAVER_PORT:-62279}" \
  --no-proxy-headers
