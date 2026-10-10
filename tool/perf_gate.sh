#!/usr/bin/env bash
# The frame perf gate (SPEC §12.9): runs Dearth's performance scenarios on a
# real display, compares them with the device's baseline, and writes a
# report. It runs unattended from start to finish, and puts the display back
# the way it found it.
#
#   tool/perf_gate.sh 10.0.1.148                     # measure, compare, report
#   tool/perf_gate.sh 10.0.1.148 --update-baseline   # measure and keep as the baseline
#   tool/perf_gate.sh 10.0.1.148 --soak 60           # also an hour of memory growth
#
# What it does:
#   1. Asks the Dearth on the display what it is (demo, joined to a Hub, on
#      its own, Toybox only) over ADB; the app answers on logcat.
#   2. Builds a profile APK whose entry point is the scenarios
#      (apps/dearth_app/integration_test/perf_test.dart).
#   3. A display joined to a Hub is reset first, so every run measures a
#      clean install: the app asks its Hub for a single-use rejoin code for
#      itself, then its data is cleared. Displays that hold the family's only
#      copy (on its own, Toybox only) and demo displays are never reset.
#   4. Installs the scenarios over Dearth (same package and signature),
#      reads one result per scenario from logcat (FreeKiosk relaunches the
#      app on each install, which is how the scenarios start).
#   5. Puts the installed Dearth back, even when the run fails, and a reset
#      display rejoins its Hub as the same device (its settings are on the
#      Hub) and gets FreeKiosk's key again; the gate waits until it syncs.
#      A scenario that comes out slower than the baseline is measured once
#      more, right away; it fails only if it's slower both times.
#   6. Writes the report (Markdown, beside the logs) and prints its path.
#
# A scenario fails when its p90 frame, build or raster time grows by more
# than 25 % (and 2 ms), its frames over 50 ms by more than 30 % (and 5),
# idle CPU by more than 3 points, or memory by more than 15 %. The SPEC §12.1
# budgets are shown beside each scenario; known misses (the Toybox scroll is
# GPU-bound on the JT215M, §12.2) don't fail the gate, getting worse does.
# Exit codes: 0 passed, 1 slower than the baseline or the run failed,
# 2 bad arguments, 3 the display couldn't be put back (the report says how).
#
# Options:
#   --update-baseline  Keep this run as the device's baseline (commit it).
#   --soak MINUTES     Add a memory soak of this many minutes (SPEC: 60).
#   --only SCENARIO    Measure one scenario (home_idle, navigate, agenda_fling,
#                      week_paging, month_open, toybox_scroll, bubbles, paint,
#                      screensaver); a probe, never a baseline.
#   --no-reset         Measure over the display's data, joined or not.
#   --reboot           Reboot the display and let it settle before measuring.
#   --no-build         Reuse the last profile APK.
#   --keep             Leave the profile build installed (to look around); a
#                      reset display stays unpaired until the next run.
#
# Needs adb, flutter, python3. Release builds for displays need a green
# gate on the frame (SPEC §12.9).

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP=app.dearth
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/dearth/perf"
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/dearth"

DEVICE="" UPDATE=0 SOAK=0 BUILD=1 KEEP=0 ONLY="" RESET_OK=1 REBOOT=0
while [ $# -gt 0 ]; do
  case "$1" in
    --update-baseline) UPDATE=1 ;;
    --soak) SOAK="${2:?--soak needs minutes}"; shift ;;
    --only) ONLY="${2:?--only needs a scenario}"; shift ;;
    --no-reset) RESET_OK=0 ;;
    --reboot) REBOOT=1 ;;
    --no-build) BUILD=0 ;;
    --keep) KEEP=1 ;;
    -h | --help) awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"; exit 0 ;;
    -*) echo "unknown option $1" >&2; exit 2 ;;
    *) DEVICE="$1" ;;
  esac
  shift
done
[ -n "$DEVICE" ] || { echo "usage: tool/perf_gate.sh <device-ip[:port]> [--update-baseline] [--soak MINUTES] [--only SCENARIO] [--no-reset]" >&2; exit 2; }
[[ "$SOAK" =~ ^[0-9]+$ ]] || { echo "--soak is a number of minutes" >&2; exit 2; }
[ -z "$ONLY" ] || [ $UPDATE = 0 ] || { echo "--only is a probe: it can't make a baseline" >&2; exit 2; }

case "$DEVICE" in *:*) SERIAL="$DEVICE" ;; *) SERIAL="$DEVICE:5555" ;; esac
adb_() { adb -s "$SERIAL" "$@"; }
sh_() { adb -s "$SERIAL" shell "$@" 2>/dev/null | tr -d '\r' || true; }
say() { printf '%s\n' "$*"; }
# A field of a JSON object, or nothing (also for no or bad JSON).
json() { python3 -I -c '
import json, sys
try:
    v = json.loads(sys.argv[1]).get(sys.argv[2])
except Exception:
    v = None
print("" if v is None else v)' "$1" "$2"; }

adb connect "$SERIAL" >/dev/null 2>&1 || true
[ "$(adb -s "$SERIAL" get-state 2>/dev/null || true)" = device ] || { echo "can't reach $SERIAL (adb connect $SERIAL)" >&2; exit 1; }
MODEL=$(sh_ getprop ro.product.model | tr -c 'A-Za-z0-9_-' '_' | sed 's/_*$//')
ABI=$(sh_ getprop ro.product.cpu.abi)
case "$ABI" in
  armeabi-v7a) TARGET=android-arm ;;
  arm64-v8a) TARGET=android-arm64 ;;
  x86_64) TARGET=android-x64 ;;
  *) echo "no Dearth build for $ABI" >&2; exit 1 ;;
esac
BASELINE="$ROOT/tool/perf/baseline-$MODEL.json"
mkdir -p "$CACHE"
RUN="$CACHE/$MODEL-$(date +%Y%m%d-%H%M%S)"
STARTED=$(date '+%Y-%m-%d %H:%M')
say "Perf gate on $MODEL ($SERIAL, $ABI)"

# What the report says the gate did, in order.
STEPS=()
step() { STEPS+=("$*"); say "  $*"; }

# Asks the Dearth on the display (frame_tool.dart) and prints its one-line
# JSON answer, or nothing within [seconds]. The answer is a
# `DEARTH_TOOL <what> {json}` line on logcat (tag DearthTool).
ask() { # ask <what> <seconds> [am start extras…]
  local what=$1 wait=$2 line=""
  shift 2
  adb_ logcat -c 2>/dev/null || true
  adb_ shell am start -n "$APP/.MainActivity" "$@" >/dev/null 2>&1 || true
  for _ in $(seq 1 "$wait"); do
    line=$(adb_ logcat -d -v raw -s DearthTool:I 2>/dev/null | tr -d '\r' | sed -n "s/^DEARTH_TOOL $what //p" | tail -n 1)
    [ -n "$line" ] && break
    sleep 1
  done
  printf '%s' "$line"
}

# 6. The report, at the end or as soon as something fails.
RAN=ok AGAIN="" RESET=0 SWAPPED=0 REJOINED="not needed" RESTORED="not needed" PSS="" COMMIT="" DIRTY=""
finish() {
  case "$MODE" in
    hub) WAS="joined to the Hub at $HUB as \"$DEVICE_NAME\"" ;;
    solo) WAS="on its own (never reset)" ;;
    toybox) WAS="Toybox only (never reset)" ;;
    demo) WAS="a demo household" ;;
    none) WAS="not set up" ;;
    *) WAS="unknown (it didn't answer)" ;;
  esac
  AFTER="Dearth put back: $RESTORED$([ "$REJOINED" = "not needed" ] || printf '; the Hub: %s' "$REJOINED")"
  python3 -I - "$RUN.context.json" "$MODEL · $STARTED" "$RUN.md" "$RUN.jsonl" "$RUN.log" "$BASELINE" \
    "Device" "$MODEL ($SERIAL, $ABI)" "When" "$STARTED" "Scenarios built from" "$COMMIT$DIRTY" \
    "Installed Dearth" "${INSTALLED:-none}" "The display was" "$WAS" "Afterwards" "$AFTER" -- "${STEPS[@]}" <<'PY'
import json, sys
out, title, report, results, log, baseline, *rest = sys.argv[1:]
split = rest.index("--")
pairs, steps = rest[:split], rest[split + 1:]
json.dump({
    "title": f"Perf gate · {title}",
    "facts": [pairs[i:i + 2] for i in range(0, len(pairs), 2)],
    "steps": steps,
    "files": [["Report", report], ["Results", results], ["Logcat", log], ["Baseline", baseline]],
}, open(out, "w"), indent=2, ensure_ascii=False)
PY

  args=("$RUN.jsonl" "$BASELINE" --pss-kb "${PSS:-0}" --model "$MODEL" --report "$RUN.md" --context "$RUN.context.json")
  [ $UPDATE = 0 ] || [ "$RAN" != ok ] || args+=(--update)
  [ "$RAN" = ok ] || args+=(--run-failed "$RAN")
  [ -z "$AGAIN" ] || args+=(--again "$AGAIN")
  status=0
  python3 -I "$ROOT/tool/perf/compare.py" "${args[@]}" || status=1
  # The display not put back matters more than any number.
  if [[ "$RESTORED" == failed* ]] || [[ "$REJOINED" == failed* ]]; then
    echo "✗ The display wasn't put back: see the report." >&2
    status=3
  fi
  exit $status
}
fail() {
  RAN="$*"
  echo "✗ $RAN" >&2
  step "Stopped: $RAN."
  # Back as it was: the saved Dearth if the scenarios went in, the Hub if
  # the display was reset.
  if declare -F put_back >/dev/null && { [ $SWAPPED = 1 ] || [ $RESET = 1 ]; }; then
    put_back
    step "Put the installed Dearth back: $RESTORED."
    [ "$REJOINED" = "not needed" ] || step "Rejoined the Hub: $REJOINED."
  fi
  finish
}

# 1. What the display is. (A leftover scenario filter from a run that died
# would quietly skip scenarios.)
sh_ setprop debug.dearth.perf_only "''" >/dev/null
INSTALLED=$(sh_ dumpsys package "$APP" | sed -n 's/^ *versionName=//p' | head -n 1)
SESSION="" MODE=unknown HUB="" DEVICE_ID="" DEVICE_NAME=""
if [ -n "$INSTALLED" ]; then
  SESSION=$(ask session 20 --es dearth_tool session)
  if [ -n "$SESSION" ]; then
    MODE=$(json "$SESSION" mode) HUB=$(json "$SESSION" hub) DEVICE_ID=$(json "$SESSION" device) DEVICE_NAME=$(json "$SESSION" name)
  fi
fi
case "$MODE" in
  hub) say "  Dearth $INSTALLED, joined to the Hub at $HUB as \"$DEVICE_NAME\" ($(json "$SESSION" sync))" ;;
  solo) say "  Dearth $INSTALLED, on its own (it holds the family's only copy: never reset)" ;;
  toybox) say "  Dearth $INSTALLED, Toybox only (its levels live on it: never reset)" ;;
  demo) say "  Dearth $INSTALLED, demo household" ;;
  none) say "  Dearth $INSTALLED, not set up yet" ;;
  *)
    if [ -z "$INSTALLED" ]; then
      say "  Dearth isn't installed"
    else
      say "  Dearth $INSTALLED didn't say what it is: a build from before 2026-10-10 can't answer, so it's measured without a reset"
    fi
    ;;
esac

# The installed Dearth, to put back afterwards.
RESTORE=""
path=$(sh_ pm path "$APP" | sed -n 's/^package://p' | head -n 1)
if [ -n "$path" ]; then
  RESTORE="$CACHE/restore-$MODEL.apk"
  adb_ pull "$path" "$RESTORE" >/dev/null 2>&1
  step "Saved the installed Dearth ($INSTALLED) to put back afterwards."
fi

APK="$ROOT/apps/dearth_app/build/app/outputs/flutter-apk/app-$ABI-profile.apk"
COMMIT=$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)
DIRTY=$([ -z "$(git -C "$ROOT" status --porcelain -- apps packages 2>/dev/null)" ] || echo " + local changes")
if [ $BUILD = 1 ]; then
  say "  building the profile scenarios (a few minutes)…"
  (cd "$ROOT/apps/dearth_app" &&
    flutter build apk --profile --split-per-abi --target-platform "$TARGET" -t integration_test/perf_test.dart \
      --dart-define=PERF_SOAK_MINUTES="$SOAK" --dart-define=PERF_ONLY="$ONLY" >"$RUN.build.log" 2>&1) || { tail -n 30 "$RUN.build.log" >&2; fail "the profile build failed (log: $RUN.build.log)"; }
  step "Built the profile scenarios from $COMMIT$DIRTY."
fi
[ -f "$APK" ] || fail "no profile APK at $APK (drop --no-build)"

# 3. A display joined to a Hub starts clean, with its way back in hand.
RESET=0 REJOIN_CODE="" REJOINED="not needed"
if [ "$MODE" = hub ] && [ $RESET_OK = 1 ]; then
  # Long enough for the run, the soak and a slow reinstall.
  ticket=$(ask rejoin 30 --es dearth_tool "rejoin:$((30 + SOAK))")
  [ -n "$ticket" ] || ticket='{"error": "no answer from the app"}'
  REJOIN_CODE=$(json "$ticket" code)
  if [ -n "$REJOIN_CODE" ] && [ "$(json "$ticket" device)" = "$DEVICE_ID" ]; then
    # Kept beside the logs (only this user can read it) in case this
    # script dies before it can use it: tool/perf_gate.sh prints how.
    (umask 077 && printf '%s %s\n' "$HUB" "$REJOIN_CODE" >"$RUN.rejoin")
    adb_ shell pm clear "$APP" >/dev/null
    RESET=1 REJOINED=pending
    step "Reset the display: the Hub issued a single-use rejoin code for \"$DEVICE_NAME\", then the app's data was cleared."
  else
    why=$(json "$ticket" error)
    step "Measured without a reset: the display couldn't get a rejoin code from its Hub (${why:-it answered for another device})."
  fi
elif [ "$MODE" = hub ]; then
  step "Measured over the display's data (--no-reset)."
fi

# 5. Putting the display back, also when anything above fails.
LOGCAT_PID="" PUT_BACK=0 SWAPPED=0 RESTORED="not needed"
# Waits (up to ~3 min) for the display to sync live again; prints the
# last phase it reported.
wait_live() {
  local sync=""
  for _ in $(seq 1 18); do
    sync=$(json "$(ask session 10 --es dearth_tool session)" sync 2>/dev/null || true)
    [ "$sync" = live ] && break
    sleep 5
  done
  printf '%s' "$sync"
}
rejoin() {
  local key="" result sync=""
  [ -f "$CONFIG/freekiosk-${SERIAL%%:*}.key" ] && key=$(cat "$CONFIG/freekiosk-${SERIAL%%:*}.key")
  # The app comes back on its onboarding screen; it claims the code itself.
  result=$(ask enroll 60 --es dearth_hub "$HUB" --es dearth_enroll "$REJOIN_CODE" ${key:+--es freekiosk_api_key "$key" --ei freekiosk_port 8080})
  if [ -z "$result" ] || [ -n "$(json "$result" error)" ]; then
    local why="the app gave no answer"
    [ -z "$result" ] || why=$(json "$result" error)
    REJOINED="failed: $why"
    return 1
  fi
  [ "$(json "$result" device)" = "$DEVICE_ID" ] || { REJOINED="failed: it came back as $(json "$result" device), not $DEVICE_ID"; return 1; }
  # What a fresh install loses besides its data: drawing over apps
  # (KioskWatch, see deploy_frame.sh).
  sh_ appops set "$APP" SYSTEM_ALERT_WINDOW allow >/dev/null
  sync=$(wait_live)
  rm -f "$RUN.rejoin"
  if [ "$sync" = live ]; then
    REJOINED="yes: \"$DEVICE_NAME\" is back on $HUB as the same device and syncing${key:+, with the FreeKiosk key handed back}"
  else
    REJOINED="joined as the same device, but not syncing yet (last: ${sync:-no answer}); check Settings → Hub & devices"
  fi
}
put_back() {
  [ $PUT_BACK = 0 ] || return 0
  PUT_BACK=1
  [ -z "$LOGCAT_PID" ] || kill "$LOGCAT_PID" 2>/dev/null || true
  [ $KEEP = 0 ] || { RESTORED="no (--keep)"; return 0; }
  if [ -n "$RESTORE" ] && [ $SWAPPED = 1 ]; then
    if adb_ install -r "$RESTORE" >/dev/null 2>&1; then
      RESTORED="yes ($INSTALLED)"
    else
      RESTORED="failed: install it by hand (adb -s $SERIAL install -r $RESTORE)"
      return 0
    fi
    adb_ shell am start -n "$APP/.MainActivity" >/dev/null 2>&1 || true
  fi
  if [ $RESET = 1 ]; then
    rejoin || true
  elif [ "$MODE" = hub ] && [ $SWAPPED = 1 ]; then
    # Not reset: it must still be joined and syncing after the scenarios.
    local sync
    sync=$(wait_live)
    if [ "$sync" = live ]; then
      REJOINED="not needed (still joined and syncing)"
    else
      REJOINED="failed: still joined but not syncing after the run (last: ${sync:-no answer}); check Settings → Hub & devices"
    fi
  fi
}
trap 'put_back; [ ! -f "$RUN.rejoin" ] || echo "The display is still unpaired. Its rejoin code is in $RUN.rejoin (Hub, code): adb -s $SERIAL shell am start -n $APP/.MainActivity --es dearth_hub <Hub> --es dearth_enroll <code>" >&2' EXIT

# --reboot: a fresh boot first. (Not the default: navigate swung between
# ~95 and ~160 ms on the JT215M with or without one, see PROGRESS
# 2026-10-10.) ADB over the network drops with the reboot, and so do its
# reverse ports (a test Hub reached through one): both come back.
if [ $REBOOT = 1 ]; then
  up=$(sh_ cat /proc/uptime | cut -d. -f1)
  reverses=$(adb_ reverse --list 2>/dev/null | awk '{print $2, $3}')
  say "  rebooting the display (up $((${up:-0} / 3600)) h)…"
  adb_ reboot >/dev/null 2>&1 || true
  sleep 20
  booted=0
  for _ in $(seq 1 60); do
    adb connect "$SERIAL" >/dev/null 2>&1 || true
    [ "$(sh_ getprop sys.boot_completed)" = 1 ] && { booted=1; break; }
    sleep 5
  done
  [ $booted = 1 ] || fail "the display didn't come back within five minutes of the reboot"
  while read -r remote local; do
    [ -z "$remote" ] || adb_ reverse "$remote" "$local" >/dev/null 2>&1 || true
  done <<<"$reverses"
  # Boot work (FreeKiosk, the media scanner, Dearth's own start) settles.
  sleep 90
  step "Rebooted the display (it had been up $((${up:-0} / 3600)) h) and let it settle for 90 s."
fi

# 4. The scenarios. Results come as `PERF_RESULT {json}` lines on the
# flutter tag.
adb_ logcat -c
# adb itself, not the adb_ function: $! must be the process to stop.
adb -s "$SERIAL" logcat -v raw -s flutter >"$RUN.log" 2>/dev/null &
LOGCAT_PID=$!
SWAPPED=1
adb_ install -r "$APK" >/dev/null 2>&1 || fail "installing the profile build failed"
adb_ shell am start -n "$APP/.MainActivity" >/dev/null 2>&1 || true
say "  running the scenarios (about six minutes$([ "$SOAK" = 0 ] || printf ' plus %s of soak' "$SOAK"))…"
deadline=$((SECONDS + 900 + SOAK * 60))
while [ $SECONDS -lt $deadline ]; do
  grep -q "^PERF_DONE\|^PERF_FAILED" "$RUN.log" && break
  sleep 5
done
PSS=$(sh_ dumpsys meminfo "$APP" | sed -n 's/^ *TOTAL PSS: *\([0-9]*\).*/\1/p;s/^ *TOTAL *\([0-9][0-9]*\) .*/\1/p' | head -n 1)
kill "$LOGCAT_PID" 2>/dev/null || true
LOGCAT_PID=""
grep "^PERF_RESULT " "$RUN.log" | sed 's/^PERF_RESULT //' >"$RUN.jsonl" || true
if grep -q "^PERF_FAILED" "$RUN.log"; then
  sed -n '/^PERF_FAILED/,$p' "$RUN.log" | head -n 30 >&2
  RAN="the scenarios failed (log: $RUN.log)"
elif ! grep -q "^PERF_DONE" "$RUN.log"; then
  RAN="no result within the time limit (log: $RUN.log)"
fi
step "Ran $(grep -c . "$RUN.jsonl" || echo 0) scenarios$([ "$SOAK" = 0 ] || printf ' and a %s-minute soak' "$SOAK"); $([ "$RAN" = ok ] && echo "all finished" || echo "$RAN")."

# A scenario slower than the baseline gets a second measurement before it
# fails the gate: the scenarios read which to run from a property, so the
# installed build runs again without a new one.
if [ "$RAN" = ok ] && [ $UPDATE = 0 ] && [ -f "$BASELINE" ]; then
  slower=$(python3 -I "$ROOT/tool/perf/compare.py" "$RUN.jsonl" "$BASELINE" --list-slower)
  if [ -n "$slower" ]; then
    say "  measuring again: $slower…"
    sh_ setprop debug.dearth.perf_only "$slower"
    adb_ logcat -c
    adb -s "$SERIAL" logcat -v raw -s flutter >"$RUN.again.log" 2>/dev/null &
    LOGCAT_PID=$!
    adb_ shell am force-stop "$APP" >/dev/null 2>&1 || true
    adb_ shell am start -n "$APP/.MainActivity" >/dev/null 2>&1 || true
    deadline=$((SECONDS + 600))
    while [ $SECONDS -lt $deadline ]; do
      grep -q "^PERF_DONE\|^PERF_FAILED" "$RUN.again.log" && break
      sleep 5
    done
    kill "$LOGCAT_PID" 2>/dev/null || true
    LOGCAT_PID=""
    sh_ setprop debug.dearth.perf_only "''" >/dev/null
    grep "^PERF_RESULT " "$RUN.again.log" | sed 's/^PERF_RESULT //' >"$RUN.again.jsonl" || true
    if grep -q . "$RUN.again.jsonl"; then
      AGAIN="$RUN.again.jsonl"
      step "Measured again what came out slower than the baseline ($slower)."
    else
      step "Couldn't measure $slower again (log: $RUN.again.log); the first run stands."
    fi
  fi
fi

say "  putting the display back…"
put_back
step "Put the installed Dearth back: $RESTORED."
[ "$REJOINED" = "not needed" ] || step "The Hub: $REJOINED."
finish
