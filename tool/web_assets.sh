#!/usr/bin/env bash
# Prepares the web build's database runtime in apps/dearth_app/web/:
#   * sqlite3.wasm — downloaded from the sqlite3.dart release matching the
#     locked `sqlite3` package version (re-downloaded when it changes);
#   * drift_worker.js — compiled from apps/dearth_app/tool/drift_worker.dart
#     with the locked drift version.
#
#   tool/web_assets.sh          # idempotent
#   tool/web_assets.sh --force  # rebuild both
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WEB="$ROOT/apps/dearth_app/web"
FORCE=0
[[ "${1:-}" == "--force" ]] && FORCE=1

# SHA-256 of each sqlite3.wasm release this tree has shipped: a release asset
# can be replaced after the fact, and this file runs inside the web app. A new
# sqlite3 version needs its line (the error below prints the hash to check).
declare -A SQLITE_WASM_SHA256=(
  [3.7.0]=fbcd2e8214f9231ea961e1b7706a22dd1194cfbfe6f26f13841b5aa7a0be1a1f
)
sha256() { if command -v sha256sum >/dev/null; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1; }

locked() { awk -v pkg="  $1:" '$0==pkg{f=1} f&&/version:/{gsub(/[" ]/,"",$2); print $2; exit}' "$ROOT/pubspec.lock"; }
SQLITE_VERSION="$(locked sqlite3)"
DRIFT_VERSION="$(locked drift)"

if [[ $FORCE -eq 1 || ! -f "$WEB/sqlite3.wasm" || "$(cat "$WEB/sqlite3.version" 2>/dev/null)" != "$SQLITE_VERSION" ]]; then
  echo "Downloading sqlite3.wasm for sqlite3 $SQLITE_VERSION"
  curl -fsSL --retry 3 -o "$WEB/sqlite3.wasm.tmp" \
    "https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-$SQLITE_VERSION/sqlite3.wasm"
  mv "$WEB/sqlite3.wasm.tmp" "$WEB/sqlite3.wasm"
  echo "$SQLITE_VERSION" > "$WEB/sqlite3.version"
fi
# Checked every time: also catches an LFS pointer in place of the file.
got="$(sha256 "$WEB/sqlite3.wasm")"
want="${SQLITE_WASM_SHA256[$SQLITE_VERSION]:-}"
if [[ "$got" != "$want" ]]; then
  echo "sqlite3.wasm for sqlite3 $SQLITE_VERSION has SHA-256 $got; expected ${want:-(no hash recorded for this version)}." >&2
  echo "If it's a new sqlite3 release, check the hash against the release page and add it to SQLITE_WASM_SHA256 in tool/web_assets.sh." >&2
  exit 1
fi

if [[ $FORCE -eq 1 || ! -f "$WEB/drift_worker.js" || "$(cat "$WEB/drift_worker.version" 2>/dev/null)" != "$DRIFT_VERSION" ]]; then
  echo "Compiling drift_worker.js for drift $DRIFT_VERSION"
  (cd "$ROOT/apps/dearth_app" && dart compile js -O4 --no-source-maps -o web/drift_worker.js tool/drift_worker.dart >/dev/null)
  rm -f "$WEB/drift_worker.js.deps" "$WEB/drift_worker.js.map"
  echo "$DRIFT_VERSION" > "$WEB/drift_worker.version"
fi
echo "web assets ready (sqlite3 $SQLITE_VERSION, drift $DRIFT_VERSION)"
