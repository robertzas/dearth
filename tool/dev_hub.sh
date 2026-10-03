#!/usr/bin/env bash
# Runs the Hub from source for development.
#
#   tool/dev_hub.sh            # demo household, fake providers, port 8090
#   tool/dev_hub.sh --real     # real providers (needs network/API keys)
#   tool/dev_hub.sh --fresh    # wipe the dev data dir first
#
# Serves apps/dearth_app/build/web when it exists (flutter build web).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATA="${DEARTH_DEV_DATA:-$ROOT/tool/.work/hub-data}"
FAKE=1; FRESH=0
for arg in "$@"; do
  case "$arg" in
    --real) FAKE=0 ;;
    --fresh) FRESH=1 ;;
    -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done
[[ $FRESH -eq 1 ]] && rm -rf "$DATA"
mkdir -p "$DATA"
export DEARTH_DATA_DIR="$DATA"
export DEARTH_PORT="${DEARTH_PORT:-8090}"
export DEARTH_ADMIN_PASSWORD="${DEARTH_ADMIN_PASSWORD:-dev}"
export DEARTH_SEED_DEMO="${DEARTH_SEED_DEMO:-1}"
export DEARTH_FAKE_PROVIDERS="$FAKE"
export DEARTH_WEB_DIR="${DEARTH_WEB_DIR:-$ROOT/apps/dearth_app/build/web}"
export DEARTH_LOG_LEVEL="${DEARTH_LOG_LEVEL:-info}"
export TZ="${TZ:-America/Denver}"
echo "Hub data: $DATA — http://localhost:$DEARTH_PORT (admin password: $DEARTH_ADMIN_PASSWORD)"
cd "$ROOT/hub/dearth_hub"
exec dart run bin/dearth_hub.dart serve
