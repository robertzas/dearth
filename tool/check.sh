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
#   tool/check.sh --only=analyze,app   # just these steps: codegen, analyze,
#                            # core, integrations, hub, ui, app (CI runs each
#                            # group on its own runner)
#   tool/check.sh --only=app --shard=2/4   # the app's test files split four
#                            # ways (balanced by size); this runs the second
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

FAST=0; E2E=0; SERIAL=0; ONLY=""; SHARD=""
for arg in "$@"; do
  case "$arg" in
    --fast) FAST=1 ;;
    --e2e) E2E=1 ;;
    --serial) SERIAL=1 ;;
    --only=*) ONLY=",${arg#--only=}," ;;
    --shard=*) SHARD="${arg#--shard=}" ;;
    -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

step() { printf '\n\033[1;34m▶ %s\033[0m\n' "$*"; }
ok() { printf '\033[1;32m✔ %s\033[0m\n' "$*"; }
bad() { printf '\033[1;31m✘ %s\033[0m\n' "$*"; }

step "Resolving workspace dependencies"
flutter pub get >/dev/null
ok "dependencies"

# With --only, a step runs when it's named; otherwise everything runs.
wanted() { [[ -z "$ONLY" || "$ONLY" == *",$1,"* ]]; }

# The app's test files for --shard=I/N: largest first, each to the lightest
# shard so far (a file's fixed cost, compiling the app, counts as ~8 KB).
app_test_files() {
  local index=${SHARD%/*} total=${SHARD#*/}
  (cd apps/dearth_app && for f in $(find test -name '*_test.dart' | sort); do echo "$(wc -c <"$f") $f"; done) |
    sort -k1,1nr -k2,2 |
    awk -v n="$total" -v want="$index" '{
      best = 1; for (s = 2; s <= n; s++) if (load[s] < load[best]) best = s
      load[best] += $1 + 8000; if (best == want) print $2
    }' | tr '\n' ' '
}

if [[ $FAST -eq 0 ]] && { [[ -z "$ONLY" ]] || wanted codegen; }; then
  step "Generating code"
  "$ROOT/tool/codegen.sh" >/dev/null
  ok "codegen"
fi

# name|directory|command
JOBS=()
wanted analyze && JOBS+=("analyze|.|flutter analyze --no-pub")
for entry in core:packages/dearth_core integrations:packages/dearth_integrations hub:hub/dearth_hub; do
  name=${entry%%:*}; pkg=${entry#*:}
  if wanted "$name" && find "$pkg/test" -name '*_test.dart' 2>/dev/null | grep -q .; then
    JOBS+=("$name|$pkg|dart test --reporter compact")
  fi
done
if wanted ui && find packages/dearth_ui/test -name '*_test.dart' 2>/dev/null | grep -q .; then
  JOBS+=("ui|packages/dearth_ui|flutter test --no-pub --reporter compact")
fi
if wanted app; then
  files=""
  [[ -n "$SHARD" ]] && files=$(app_test_files)
  if [[ -z "$SHARD" || -n "$files" ]]; then
    JOBS+=("app${SHARD:+ $SHARD}|apps/dearth_app|flutter test --no-pub --reporter compact $files")
  fi
fi

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
  [[ ${#JOBS[@]} -gt 0 ]] && step "Analyzing and testing ${#JOBS[@]} things at once (logs in $LOGS)"
  declare -A NAME_OF
  for job in "${JOBS[@]}"; do
    IFS='|' read -r name dir cmd <<<"$job"
    log="$LOGS/${name//[\/ ]/_}.log"
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
    secs=$(cat "$LOGS/${name//[\/ ]/_}.log.time" 2>/dev/null || echo '?')
    if [[ $rc -eq 0 ]]; then ok "$name (${secs}s)"; else bad "$name (${secs}s)"; FAILED+=("$name"); fi
    left=$((left - 1))
  done
  for name in "${FAILED[@]}"; do
    printf '\n\033[1;31m── %s ──\033[0m\n' "$name"
    cat "$LOGS/${name//[\/ ]/_}.log"
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
