#!/usr/bin/env bash
# The local quality gate (PROGRESS.md "How to resume"): resolves the workspace,
# regenerates code, analyzes everything and runs every unit-test suite.
#
#   tool/check.sh            # full gate
#   tool/check.sh --fast     # skip codegen
#   tool/check.sh --e2e      # also run the Playwright web E2E suite (slow)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

FAST=0; E2E=0
for arg in "$@"; do
  case "$arg" in
    --fast) FAST=1 ;;
    --e2e) E2E=1 ;;
    -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

step() { printf '\n\033[1;34m▶ %s\033[0m\n' "$*"; }
ok() { printf '\033[1;32m✔ %s\033[0m\n' "$*"; }

step "Resolving workspace dependencies"
flutter pub get >/dev/null
ok "dependencies"

if [[ $FAST -eq 0 ]]; then
  step "Generating code"
  "$ROOT/tool/codegen.sh" >/dev/null
  ok "codegen"
fi

step "Analyzing all packages"
flutter analyze --no-pub
ok "analyze"

for pkg in packages/dearth_core packages/dearth_integrations hub/dearth_hub; do
  if compgen -G "$pkg/test/*_test.dart" >/dev/null || compgen -G "$pkg/test/**/*_test.dart" >/dev/null; then
    step "Testing $pkg"
    (cd "$pkg" && dart test --reporter compact)
    ok "$pkg"
  fi
done

for pkg in packages/dearth_ui apps/dearth_app; do
  if [[ -d "$pkg/test" ]] && find "$pkg/test" -name '*_test.dart' | grep -q .; then
    step "Testing $pkg"
    (cd "$pkg" && flutter test --no-pub --reporter compact)
    ok "$pkg"
  fi
done

if [[ $E2E -eq 1 ]]; then
  step "Playwright web E2E"
  "$ROOT/tool/e2e.sh"
  ok "e2e"
fi

printf '\n\033[1;32mAll checks passed.\033[0m\n'
