#!/usr/bin/env bash
# Write .br and .gz siblings for the Flutter web build so the gateway can serve
# precompressed bundles (main.dart.js shrinks from ~9.7 MB to ~2 MB). Run after
# every `flutter build web`; stale siblings are rewritten.
set -euo pipefail

WEB_DIR="${1:?usage: compress-web.sh <web build dir>}"
command -v brotli >/dev/null || { echo "brotli is required (brew install brotli)" >&2; exit 2; }

find "$WEB_DIR" -type f \
  \( -name '*.js' -o -name '*.mjs' -o -name '*.wasm' -o -name '*.json' \
     -o -name '*.html' -o -name '*.css' -o -name '*.otf' -o -name '*.ttf' \
     -o -name '*.txt' -o -name '*.svg' \) -size +1k -print0 |
  while IFS= read -r -d '' file; do
    brotli --force --best --output="$file.br" "$file"
    gzip --force --best --keep --no-name "$file"
    touch -r "$file" "$file.br" "$file.gz"
  done
