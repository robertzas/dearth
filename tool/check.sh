#!/usr/bin/env bash
# The local quality gate (PROGRESS.md "How to resume"): resolves the workspace,
# regenerates code, then analyzes everything and runs every unit-test suite
# at the same time (they're independent once the code is generated). Each
# step logs to its own file; a failing step's log is printed at the end.
#
#   tool/check.sh            # full gate
#   tool/check.sh --fast     # skip codegen
#   tool/check.sh --e2e      # also run the Playwright web E2E suite (slow)
#   tool/check.sh --serial   # one step at a time, output as it goes
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

FAST=0; E2E=0; SERIAL=0
for arg in "$@"; do
  case "$arg" in
    --fast) FAST=1 ;;
    --e2e) E2E=1 ;;
    --serial) SERIAL=1 ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

step() { printf '\n\033[1;34m▶ %s\033[0m\n' "$*"; }
ok() { printf '\033[1;32m✔ %s\033[0m\n' "$*"; }
bad() { printf '\033[1;31m✘ %s\033[0m\n' "$*"; }

step "Resolving workspace dependencies"
flutter pub get >/dev/null
ok "dependencies"

if [[ $FAST -eq 0 ]]; then
  step "Generating code"
  "$ROOT/tool/codegen.sh" >/dev/null
  ok "codegen"
fi

# name|directory|command
JOBS=("analyze|.|flutter analyze --no-pub")
for pkg in packages/dearth_core packages/dearth_integrations hub/dearth_hub; do
  if find "$pkg/test" -name '*_test.dart' 2>/dev/null | grep -q .; then
    JOBS+=("$pkg|$pkg|dart test --reporter compact")
  fi
done
for pkg in packages/dearth_ui apps/dearth_app; do
  if find "$pkg/test" -name '*_test.dart' 2>/dev/null | grep -q .; then
    JOBS+=("$pkg|$pkg|flutter test --no-pub --reporter compact")
  fi
done

FAILED=()
if [[ $SERIAL -eq 1 ]]; then
  for job in "${JOBS[@]}"; do
    IFS='|' read -r name dir cmd <<<"$job"
    step "$name"
    if (cd "$dir" && $cmd); then ok "$name"; else bad "$name"; FAILED+=("$name"); fi
  done
else
  LOGS="$(mktemp -d "${TMPDIR:-/tmp}/dearth-check.XXXXXX")"
  trap 'kill $(jobs -p) 2>/dev/null || true' INT TERM
  step "Analyzing and testing ${#JOBS[@]} things at once (logs in $LOGS)"
  declare -A NAME_OF
  for job in "${JOBS[@]}"; do
    IFS='|' read -r name dir cmd <<<"$job"
    log="$LOGS/${name//\//_}.log"
    ( set +e; start=$SECONDS; cd "$dir" && $cmd >"$log" 2>&1; rc=$?; echo "$((SECONDS - start))" >"$log.time"; exit $rc ) &
    NAME_OF[$!]=$name
  done
  # Report each step as it finishes, in finishing order.
  left=${#JOBS[@]}
  while [[ $left -gt 0 ]]; do
    set +e
    wait -n -p done_pid
    rc=$?
    set -e
    name=${NAME_OF[$done_pid]}
    secs=$(cat "$LOGS/${name//\//_}.log.time" 2>/dev/null || echo '?')
    if [[ $rc -eq 0 ]]; then ok "$name (${secs}s)"; else bad "$name (${secs}s)"; FAILED+=("$name"); fi
    left=$((left - 1))
  done
  for name in "${FAILED[@]}"; do
    printf '\n\033[1;31m── %s ──\033[0m\n' "$name"
    cat "$LOGS/${name//\//_}.log"
  done
  [[ ${#FAILED[@]} -gt 0 ]] || rm -rf "$LOGS"
fi

if [[ ${#FAILED[@]} -gt 0 ]]; then
  printf '\n\033[1;31mFailed: %s\033[0m\n' "${FAILED[*]}"
  exit 1
fi

if [[ $E2E -eq 1 ]]; then
  step "Playwright web E2E"
  "$ROOT/tool/e2e.sh"
  ok "e2e"
fi

printf '\n\033[1;32mAll checks passed.\033[0m\n'
