#!/usr/bin/env bash
# Reads app/.env and forwards it as --dart-define flags, so `SUPABASE_URL`/
# `SUPABASE_ANON_KEY` live in one gitignored file instead of being retyped (or
# hardcoded into a local launch.json) every time.
#
# Usage: ./run.sh run -d linux
#        ./run.sh build apk --release --obfuscate --split-debug-info=build/symbols
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

if [ ! -f .env ]; then
  echo "app/.env not found -- copy app/.env.example to app/.env and fill in real values." >&2
  exit 1
fi

set -a
# shellcheck disable=SC1091
source .env
set +a

if [ -z "${SUPABASE_URL:-}" ] || [ -z "${SUPABASE_ANON_KEY:-}" ]; then
  echo "SUPABASE_URL / SUPABASE_ANON_KEY missing from app/.env" >&2
  exit 1
fi

exec flutter "$@" \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY"
