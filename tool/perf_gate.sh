#!/usr/bin/env bash
# The frame perf gate (SPEC §12.9): runs Dearth's performance scenarios on a
# real display and fails if one got slower than the device's baseline.
#
#   tool/perf_gate.sh 10.0.1.148                     # measure and compare
#   tool/perf_gate.sh 10.0.1.148 --update-baseline   # measure and keep as the baseline
#   tool/perf_gate.sh 10.0.1.148 --soak 60           # also an hour of memory growth
#
# It builds a profile APK whose entry point is the scenarios
# (apps/dearth_app/integration_test/perf_test.dart), installs it over the
# Dearth on the device (same package and signature: its data stays), reads
# one result per scenario from logcat, and puts the APK that was installed
# back, even when the run fails. The kiosk keeps running: FreeKiosk
# relaunches the app on each install, which is how the scenarios start.
#
# Results are compared with tool/perf/baseline-<model>.json (checked in):
# a scenario fails when its p90 frame, build or raster time grows by more
# than 15 % (and 1 ms), its janky frames by more than 5 points, frames over
# 50 ms by more than 3, idle CPU by more than 2 points, or memory by more
# than 15 %. The SPEC §12.1 budgets are printed beside each scenario; known
# misses (the Toybox scroll is GPU-bound on the JT215M, §12.2) don't fail
# the gate, getting worse does.
#
# Options:
#   --update-baseline  Keep this run as the device's baseline (commit it).
#   --soak MINUTES     Add a memory soak of this many minutes (SPEC: 60).
#   --only SCENARIO    Measure one scenario (home_idle, navigate, agenda_fling,
#                      week_paging, month_open, toybox_scroll, bubbles, paint,
#                      screensaver); a probe, never a baseline.
#   --no-build         Reuse the last profile APK.
#   --keep             Leave the profile build installed (to look around).
#
# Needs adb, flutter, python3. Release builds for displays need a green
# gate on the frame (SPEC §12.9).

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP=app.dearth
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/dearth/perf"

DEVICE="" UPDATE=0 SOAK=0 BUILD=1 KEEP=0 ONLY=""
while [ $# -gt 0 ]; do
  case "$1" in
    --update-baseline) UPDATE=1 ;;
    --soak) SOAK="${2:?--soak needs minutes}"; shift ;;
    --only) ONLY="${2:?--only needs a scenario}"; shift ;;
    --no-build) BUILD=0 ;;
    --keep) KEEP=1 ;;
    -h | --help) sed -n '2,35p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "unknown option $1" >&2; exit 2 ;;
    *) DEVICE="$1" ;;
  esac
  shift
done
[ -n "$DEVICE" ] || { echo "usage: tool/perf_gate.sh <device-ip[:port]> [--update-baseline] [--soak MINUTES]" >&2; exit 2; }
[[ "$SOAK" =~ ^[0-9]+$ ]] || { echo "--soak is a number of minutes" >&2; exit 2; }
[ -z "$ONLY" ] || [ $UPDATE = 0 ] || { echo "--only is a probe: it can't make a baseline" >&2; exit 2; }

case "$DEVICE" in *:*) SERIAL="$DEVICE" ;; *) SERIAL="$DEVICE:5555" ;; esac
adb_() { adb -s "$SERIAL" "$@"; }
sh_() { adb -s "$SERIAL" shell "$@" 2>/dev/null | tr -d '\r' || true; }
say() { printf '%s\n' "$*"; }

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
say "Perf gate on $MODEL ($SERIAL, $ABI)"

# The installed Dearth, to put back afterwards.
RESTORE=""
path=$(sh_ pm path "$APP" | sed -n 's/^package://p' | head -n 1)
if [ -n "$path" ]; then
  RESTORE="$CACHE/restore-$MODEL.apk"
  adb_ pull "$path" "$RESTORE" >/dev/null
  say "  saved the installed Dearth ($(sh_ dumpsys package "$APP" | sed -n 's/^ *versionName=//p' | head -n 1))"
fi
LOGCAT_PID=""
restore() {
  [ -z "$LOGCAT_PID" ] || kill "$LOGCAT_PID" 2>/dev/null || true
  if [ $KEEP = 0 ] && [ -n "$RESTORE" ]; then
    adb_ install -r "$RESTORE" >/dev/null 2>&1 && say "  put the installed Dearth back" || say "  couldn't reinstall $RESTORE: install it by hand (adb -s $SERIAL install -r $RESTORE)"
    adb_ shell am start -n "$APP/.MainActivity" >/dev/null 2>&1 || true
  fi
}
trap restore EXIT

APK="$ROOT/apps/dearth_app/build/app/outputs/flutter-apk/app-$ABI-profile.apk"
if [ $BUILD = 1 ]; then
  say "  building the profile scenarios (a few minutes)…"
  (cd "$ROOT/apps/dearth_app" &&
    flutter build apk --profile --split-per-abi --target-platform "$TARGET" -t integration_test/perf_test.dart \
      --dart-define=PERF_SOAK_MINUTES="$SOAK" --dart-define=PERF_ONLY="$ONLY" >"$RUN.build.log" 2>&1) || { tail -n 30 "$RUN.build.log" >&2; exit 1; }
fi
[ -f "$APK" ] || { echo "no profile APK at $APK (drop --no-build)" >&2; exit 1; }

# Results come as `PERF_RESULT {json}` lines on the flutter tag.
adb_ logcat -c
# adb itself, not the adb_ function: $! must be the process to stop.
adb -s "$SERIAL" logcat -v raw -s flutter >"$RUN.log" 2>/dev/null &
LOGCAT_PID=$!
adb_ install -r "$APK" >/dev/null || { echo "install failed" >&2; exit 1; }
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
  echo "the scenarios failed (log: $RUN.log)" >&2
  exit 1
fi
grep -q "^PERF_DONE" "$RUN.log" || { echo "no result within the time limit (log: $RUN.log)" >&2; exit 1; }

args=("$RUN.jsonl" "$BASELINE" --pss-kb "${PSS:-0}" --model "$MODEL")
[ $UPDATE = 0 ] || args+=(--update)
python3 -I "$ROOT/tool/perf/compare.py" "${args[@]}"
