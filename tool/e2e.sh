#!/usr/bin/env bash
# Runs the Playwright web E2E suite (SPEC §16.1) against a fresh test Hub.
#
#   tool/e2e.sh                       # build web (if stale) + all projects
#   tool/e2e.sh --project=wall-l      # extra args go to `playwright test`
#   SKIP_BUILD=1 tool/e2e.sh          # reuse apps/dearth_app/build/web
#   CHROME_PATH=/usr/bin/google-chrome-stable tool/e2e.sh   # use a system Chrome
#   tool/e2e.sh --shard=2/20          # a twentieth of the suite (CI runs twenty)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ "${SKIP_BUILD:-0}" != "1" ]]; then
  "$ROOT/tool/web_assets.sh" >/dev/null
  (cd "$ROOT/apps/dearth_app" && flutter build web --release --no-wasm-dry-run)
fi
cd "$ROOT/e2e"
[[ -d node_modules ]] || npm ci --no-audit --no-fund
if [[ -z "${CHROME_PATH:-}" ]]; then npx playwright install chromium >/dev/null; fi
exec npx playwright test "$@"
