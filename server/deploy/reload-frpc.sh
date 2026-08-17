#!/bin/sh
set -eu

pid="$(/usr/sbin/lsof -nP -iTCP:62773 -sTCP:ESTABLISHED -t 2>/dev/null | /usr/bin/head -n 1 || true)"
if [ -n "$pid" ]; then
  /bin/kill -TERM "$pid"
fi
