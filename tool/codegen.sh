#!/usr/bin/env bash
# Regenerates drift code in dearth_core (run after editing lib/src/db/tables.dart).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT/packages/dearth_core"
dart run build_runner build "$@"
