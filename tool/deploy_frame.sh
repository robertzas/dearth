#!/usr/bin/env bash
# Sets up, checks or updates a Dearth wall display over network ADB (SPEC §15).
#
# One command turns an Android tablet or photo frame, fresh from a factory
# reset or already in use, into a Dearth kiosk:
#   • FreeKiosk (a pinned, checksum-verified release) is Device Owner and the
#     home app, locked to Dearth: it starts Dearth on boot and brings it back
#     if it exits.
#   • Magic corner: tap the bottom-right corner 5 times within 2 seconds, then
#     enter the PIN (1234), to reach FreeKiosk's settings. The volume buttons
#     just change the volume (FreeKiosk's "Volume Up 5 times" shortcut is off:
#     it swallowed every Volume Up press).
#   • Auto-rotate on. Adaptive brightness on, so the screen dims with the room
#     until Dearth sets its own from the light sensor.
#   • FreeKiosk's REST API on, with a key Dearth gets too: Dearth turns the
#     screen off at night and restarts the frame through it. The key is kept
#     in ~/.config/dearth/ on this computer.
#     The screen never times out, there is no lock screen, Android's own
#     screensaver is off (Dearth has its own) and Wi-Fi stays on.
#   • Dearth installed or updated for the device's CPU: the latest GitHub
#     release, an APK you name, or one built here.
# Every step reads the device first and changes only what differs, so running
# it again is safe. --check reports the differences and changes nothing.
#
#   tool/deploy_frame.sh 10.0.1.148                   # set up, or bring up to date
#   tool/deploy_frame.sh 10.0.1.148 --check           # report only
#   tool/deploy_frame.sh 10.0.1.148 --build           # build the APK here and install it
#   tool/deploy_frame.sh 10.0.1.148 --apk dearth.apk  # install a particular APK
#
# Options:
#   --check        Report how the device differs from the setup; change nothing.
#   --apk FILE     Install this Dearth APK instead of the latest GitHub release.
#   --build        Build the APK here (flutter build apk) and install it.
#   --no-app       Leave Dearth as it is.
#   --replace      If the new APK is signed with a different key than the
#                  installed Dearth, uninstall Dearth first. This erases
#                  Dearth's data on the device, pairing included.
#   --pin PIN      FreeKiosk PIN (default 1234): set on a fresh device, and
#                  needed to change the settings of a set-up one.
#   --corner POS   Magic corner (default bottom-right, the corner Dearth keeps
#                  free): bottom-right, bottom-left, top-right or top-left.
#   --taps N       Taps on the corner (default 5, 2 to 20) ...
#   --window MS    ... all within this many milliseconds (default 2000).
#   --tz ZONE      Time zone (default: this computer's).
#   --webview      Upgrade a System WebView older than Chromium 111 (vendor
#                  ROMs ship 74; Dearth will need it for YouTube).
#   --no-bloat     Keep the vendor apps that a known model's preset disables.
#   --reboot       Reboot at the end and check that Dearth comes back by itself.
#   --join HUB CODE  Join Dearth to a Hub with an enrollment code (Settings →
#                  Hub & devices → Add a display with a code): a display that
#                  isn't set up claims it by itself. One that is set up is
#                  left as it is.
#
# Needs adb (Android platform-tools), curl and python3; --webview also needs
# apksigner (Android SDK build-tools). Reading FreeKiosk's settings back needs
# a root ADB shell (vendor frames have one); without it the settings are sent
# on every run instead of compared.
# Env: FREEKIOSK_TAG with FREEKIOSK_SHA256 pin another FreeKiosk release;
#      DEARTH_REPO (default robertzas/dearth) is where releases come from.

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

FREEKIOSK_TAG="${FREEKIOSK_TAG:-v2.0.0-beta.4}"
FREEKIOSK_SHA256="${FREEKIOSK_SHA256:-5aa4e3b705cc711d9800eb9880ef8f8231e21f2e281980abca345d427f072194}"
DEARTH_REPO="${DEARTH_REPO:-robertzas/dearth}"
APP=app.dearth
FK=com.freekiosk
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/dearth"

CHECK=0 APK="" BUILD=0 NO_APP=0 REPLACE=0 PIN=1234 CORNER=bottom-right TAPS=5 WINDOW=2000
TZ_WANT="" WEBVIEW=0 BLOAT=1 REBOOT=0 JOIN_HUB="" JOIN_CODE=""

# ─────────────────────────────── output ────────────────────────────────────

if [ -t 1 ]; then
  BOLD=$'\033[1m' GREEN=$'\033[32m' YELLOW=$'\033[33m' RED=$'\033[31m' DIM=$'\033[2m' OFF=$'\033[0m'
else
  BOLD="" GREEN="" YELLOW="" RED="" DIM="" OFF=""
fi
CHANGES=0 DIFFS=0 PROBLEMS=0
section() { printf '\n%s%s%s\n' "$BOLD" "$*" "$OFF"; }
ok() { printf '  %s✓%s %s\n' "$GREEN" "$OFF" "$*"; }
changed() { printf '  %s→%s %s\n' "$YELLOW" "$OFF" "$*"; CHANGES=$((CHANGES + 1)); }
differs() { printf '  %s✗%s %s\n' "$YELLOW" "$OFF" "$*"; DIFFS=$((DIFFS + 1)); }
problem() { printf '  %s✗ %s%s\n' "$RED" "$*" "$OFF"; PROBLEMS=$((PROBLEMS + 1)); }
note() { printf '    %s%s%s\n' "$DIM" "$*" "$OFF"; }
die() { printf '%sError:%s %s\n' "$RED" "$OFF" "$*" >&2; exit 1; }
usage() { sed -n '2,/^$/s/^# \{0,1\}//p' "$0"; exit "${1:-0}"; }

# ─────────────────────────────── options ───────────────────────────────────

DEVICE="${1:-}"
case "$DEVICE" in "" | -h | --help) usage 0 ;; -*) usage 2 ;; esac
shift
while [ $# -gt 0 ]; do
  case "$1" in
    --check) CHECK=1 ;;
    --apk) APK="${2:?--apk needs a file}"; shift ;;
    --build) BUILD=1 ;;
    --no-app) NO_APP=1 ;;
    --replace) REPLACE=1 ;;
    --pin) PIN="${2:?--pin needs a PIN}"; shift ;;
    --corner) CORNER="${2:?--corner needs a corner}"; shift ;;
    --taps) TAPS="${2:?--taps needs a number}"; shift ;;
    --window) WINDOW="${2:?--window needs milliseconds}"; shift ;;
    --tz) TZ_WANT="${2:?--tz needs a zone}"; shift ;;
    --webview) WEBVIEW=1 ;;
    --no-bloat) BLOAT=0 ;;
    --reboot) REBOOT=1 ;;
    --join) JOIN_HUB="${2:?--join needs the Hub address and a code}" JOIN_CODE="${3:?--join needs the Hub address and a code}"; shift 2 ;;
    -h | --help) usage 0 ;;
    *) printf 'Unknown option: %s\n\n' "$1" >&2; usage 2 ;;
  esac
  shift
done
case "$CORNER" in bottom-right | bottom-left | top-right | top-left) ;; *) die "--corner is bottom-right, bottom-left, top-right or top-left" ;; esac
[[ "$TAPS" =~ ^[0-9]+$ ]] && [ "$TAPS" -ge 2 ] && [ "$TAPS" -le 20 ] || die "--taps is 2 to 20"
[[ "$WINDOW" =~ ^[0-9]+$ ]] && [ "$WINDOW" -ge 500 ] && [ "$WINDOW" -le 5000 ] || die "--window is 500 to 5000 ms"
[[ "$PIN" =~ ^[0-9]{4,6}$ ]] || die "--pin is 4 to 6 digits"
[ -z "$APK" ] || [ -f "$APK" ] || die "no such APK: $APK"
SOURCES=$((BUILD + NO_APP))
[ -z "$APK" ] || SOURCES=$((SOURCES + 1))
[ $SOURCES -le 1 ] || die "choose one of --apk, --build and --no-app"
if [ -z "$TZ_WANT" ]; then
  TZ_WANT=$(timedatectl show -p Timezone --value 2>/dev/null || true)
  [ -n "$TZ_WANT" ] || TZ_WANT=$(readlink /etc/localtime 2>/dev/null | sed -n 's#.*zoneinfo/##p')
fi

# ──────────────────────────────── tools ────────────────────────────────────

ADB="$(command -v adb || true)"
if [ -z "$ADB" ]; then
  for sdk in "${ANDROID_HOME:-}" "${ANDROID_SDK_ROOT:-}" /opt/android-sdk "$HOME/Android/Sdk" "$HOME/Library/Android/sdk"; do
    if [ -n "$sdk" ] && [ -x "$sdk/platform-tools/adb" ]; then ADB="$sdk/platform-tools/adb"; break; fi
  done
fi
[ -n "$ADB" ] || die "adb not found: install Android platform-tools"
command -v curl >/dev/null || die "curl is needed"
command -v python3 >/dev/null || die "python3 is needed"

# Nothing here reads input, and `adb shell` would swallow it: a terminal or a
# pipe on stdin made the first device queries come back empty.
exec </dev/null

WORK=$(mktemp -d)
LOGCAT_PID=""
cleanup() {
  [ -z "$LOGCAT_PID" ] || kill "$LOGCAT_PID" 2>/dev/null || true
  rm -rf "$WORK"
}
trap cleanup EXIT

case "$DEVICE" in *:*) SERIAL="$DEVICE" ;; *) SERIAL="$DEVICE:5555" ;; esac
adb_() { "$ADB" -s "$SERIAL" "$@"; }
# A device shell command's output, without carriage returns. Never fails, so
# `x=$(sh_ …)` is safe under `set -e`; check the output instead.
sh_() { "$ADB" -s "$SERIAL" shell "$@" 2>/dev/null | tr -d '\r' || true; }

sha256() { if command -v sha256sum >/dev/null; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi; }

# `setting <namespace> <key> <value> <what it means>`: one Android setting.
setting() {
  local have
  have=$(sh_ settings get "$1" "$2")
  if [ "$have" = "$3" ]; then
    ok "$4"
  elif [ $CHECK = 1 ]; then
    differs "$4 ($1 $2 is $have, should be $3)"
  else
    sh_ settings put "$1" "$2" "$3" >/dev/null
    if [ "$(sh_ settings get "$1" "$2")" = "$3" ]; then changed "$4"; else problem "$4: couldn't set $1 $2"; fi
  fi
}

# ─────────────────────────────── device ────────────────────────────────────

section "Device $SERIAL"
"$ADB" connect "$SERIAL" >/dev/null 2>&1 || true
[ "$("$ADB" -s "$SERIAL" get-state 2>/dev/null || true)" = device ] ||
  die "can't reach $SERIAL. Is the tablet on Wi-Fi with network ADB on? (try: adb connect $SERIAL)"
MODEL=$(sh_ getprop ro.product.model)
SDK=$(sh_ getprop ro.build.version.sdk)
ABI=$(sh_ getprop ro.product.cpu.abi)
ROOT_SHELL=0
[ "$(sh_ id -u)" = 0 ] && ROOT_SHELL=1
ok "$(sh_ getprop ro.product.manufacturer) $MODEL, Android $(sh_ getprop ro.build.version.release), $ABI$([ $ROOT_SHELL = 1 ] && printf ', root shell')"
[ "${SDK:-0}" -ge 24 ] || die "Dearth and FreeKiosk need Android 7 or newer"

# Known models: what a factory reset loses and the setup puts back.
DENSITY="" ANIMATION="" VENDOR_APPS=""
case "$MODEL" in
  JT215M*)
    # Joyhong JT215M-H01 (Allwinner A133, 1080×1920): Dearth's wall layouts
    # are sized for density 173. Never disable com.waophoto.fota on this ROM:
    # its patched Activity.onCreate starts it, and every app crash-loops.
    DENSITY=173
    ANIMATION=0.5
    VENDOR_APPS="com.fujia.calendar com.joyhong.test com.allwinner.batterytest com.softwinner.awlogsettings
      com.softwinner.awmanager com.softwinner.dragonaging com.softwinner.dragonaging.res com.softwinner.fireplayer
      com.softwinner.settingssetup com.android.bips com.android.bookmarkprovider com.android.calculator2
      com.android.calendar com.android.contacts com.android.deskclock com.android.dreams.basic com.android.gallery3d
      com.android.music com.android.nfc com.android.printservice.recommendation com.android.printspooler
      com.android.quicksearchbox com.android.soundrecorder"
    note "Preset: Joyhong JT215M"
    ;;
esac

# ────────────────────────────── FreeKiosk ──────────────────────────────────

section "FreeKiosk"

fetch_freekiosk() {
  local dir="$CACHE/freekiosk/$FREEKIOSK_TAG" file
  file="$dir/freekiosk.apk"
  mkdir -p "$dir"
  if [ ! -f "$file" ] || [ "$(sha256 "$file")" != "$FREEKIOSK_SHA256" ]; then
    curl -fsSL "https://github.com/RushB-fr/freekiosk/releases/download/$FREEKIOSK_TAG/freekiosk-$FREEKIOSK_TAG.apk" -o "$file.part" ||
      die "couldn't download FreeKiosk $FREEKIOSK_TAG"
    mv "$file.part" "$file"
  fi
  [ "$(sha256 "$file")" = "$FREEKIOSK_SHA256" ] || { rm -f "$file"; die "FreeKiosk $FREEKIOSK_TAG doesn't match its pinned SHA-256"; }
  printf '%s' "$file"
}

FK_WANT="${FREEKIOSK_TAG#v}"
FK_HAVE=$(sh_ dumpsys package "$FK" | sed -n 's/^ *versionName=//p' | head -n 1)
if [ "$FK_HAVE" = "$FK_WANT" ]; then
  ok "FreeKiosk $FK_HAVE installed"
elif [ $CHECK = 1 ]; then
  if [ -n "$FK_HAVE" ]; then differs "FreeKiosk $FK_HAVE is installed; this script sets up $FK_WANT"; else differs "FreeKiosk isn't installed"; fi
else
  out=$(adb_ install -r "$(fetch_freekiosk)" 2>&1 || true)
  case "$out" in
    *Success*) changed "FreeKiosk ${FK_HAVE:+$FK_HAVE → }$FK_WANT installed" ;;
    *DOWNGRADE*) problem "FreeKiosk $FK_HAVE is newer than $FK_WANT; keeping it (pin it with FREEKIOSK_TAG and FREEKIOSK_SHA256)" ;;
    *) die "FreeKiosk install failed: $out" ;;
  esac
fi

POLICY=$(sh_ dumpsys device_policy)
OWNER=$(awk '/Device Owner:/ { owner = 1 } owner && /package=/ { sub(/.*package=/, ""); print; exit }' <<<"$POLICY")
if [ "$OWNER" = "$FK" ]; then
  ok "Device Owner (full lockdown, no permission prompts)"
elif [ -n "$OWNER" ]; then
  problem "$OWNER is Device Owner. Remove it first; FreeKiosk needs to be the owner"
elif [ $CHECK = 1 ]; then
  differs "FreeKiosk isn't Device Owner"
else
  out=$(sh_ dpm set-device-owner "$FK/.DeviceAdminReceiver")
  case "$out" in
    *Success*) changed "FreeKiosk is Device Owner" ;;
    *) problem "couldn't make FreeKiosk Device Owner (remove every account in Settings → Accounts, or factory-reset): $out" ;;
  esac
fi

# Drawing over apps is how the magic corner exists at all: without it the
# overlay never appears (Device Owner doesn't grant it on every ROM). Usage
# access lets FreeKiosk see which app is in front (auto-relaunch);
# WRITE_SECURE_SETTINGS lets it switch on its accessibility service.
appop() { # appop <op> <what it allows> [package, default FreeKiosk]
  local pkg=${3:-$FK}
  if [[ "$(sh_ appops get "$pkg" "$1")" == *allow* ]]; then
    ok "$2"
  elif [ $CHECK = 1 ]; then
    differs "Not allowed: $2"
  else
    sh_ appops set "$pkg" "$1" allow >/dev/null
    changed "Allowed: $2"
  fi
}
appop SYSTEM_ALERT_WINDOW "Display over other apps (the magic corner)"
appop GET_USAGE_STATS "Usage access (auto-relaunch)"
if [[ "$(sh_ dumpsys package "$FK")" == *"WRITE_SECURE_SETTINGS: granted=true"* ]]; then
  ok "Secure settings permission"
elif [ $CHECK = 1 ]; then
  differs "FreeKiosk can't write secure settings"
else
  sh_ pm grant "$FK" android.permission.WRITE_SECURE_SETTINGS >/dev/null
  changed "Secure settings permission granted"
fi

home() { sh_ cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME | tail -n 1; }
if [[ "$(home)" == "$FK/"* ]]; then
  ok "Home app (starts on boot)"
elif [ $CHECK = 1 ]; then
  differs "Home is $(home), not FreeKiosk"
else
  sh_ cmd role add-role-holder android.app.role.HOME "$FK" >/dev/null
  [[ "$(home)" == "$FK/"* ]] || sh_ cmd package set-home-activity "$FK/.MainActivity" >/dev/null
  if [[ "$(home)" == "$FK/"* ]]; then changed "FreeKiosk is the Home app"; else problem "Home is still $(home): press Home once and choose FreeKiosk → Always"; fi
fi

# ──────────────────────────────── Dearth ───────────────────────────────────

section "Dearth"

APP_INFO=$(sh_ dumpsys package "$APP")
APP_HAVE=$(sed -n 's/^ *versionName=//p' <<<"$APP_INFO" | head -n 1)
APP_CODE=$(sed -n 's/^ *versionCode=\([0-9]*\).*/\1/p' <<<"$APP_INFO" | head -n 1)
APP_SHA=""
if [ -n "$APP_HAVE" ]; then
  APP_SHA=$(sh_ sha256sum "$(sh_ pm path "$APP" | sed -n 's/^package://p' | head -n 1)" | cut -d' ' -f1)
fi
NEW_APK="" NEW_LABEL="" NEW_SHA="" INSTALLED=0

case "$ABI" in
  armeabi-v7a) TARGET=android-arm ;;
  arm64-v8a) TARGET=android-arm64 ;;
  x86_64) TARGET=android-x64 ;;
  *) TARGET="" ;;
esac

# Flutter's split APKs carry versionCode = 1000 × ABI code + build number
# (armeabi-v7a 1, arm64-v8a 2, x86_64 4). The build number of an installed
# versionCode, or 1 when there's none.
build_number() {
  local base
  case "$ABI" in armeabi-v7a) base=1000 ;; arm64-v8a) base=2000 ;; x86_64) base=4000 ;; *) base=0 ;; esac
  if [ -n "${1:-}" ] && [ "$1" -gt "$base" ]; then echo $(($1 - base)); else echo 1; fi
}

if [ $NO_APP = 1 ]; then
  ok "Left as it is: ${APP_HAVE:-not installed}"
elif [ -z "$TARGET" ]; then
  problem "No Dearth build for $ABI"
else
  if [ -n "$APK" ]; then
    NEW_APK="$APK" NEW_LABEL=$(basename "$APK")
  elif [ $BUILD = 1 ]; then
    if [ $CHECK = 0 ]; then
      note "Building Dearth for $ABI (a few minutes)…"
      sha=$(git -C "$ROOT" describe --always --dirty 2>/dev/null || echo dev)
      # The installed build's number, so it installs in place over a newer
      # GitHub release (a lower one is a downgrade). Its "local" version
      # keeps the app's updater from replacing it (SPEC §15.3).
      (cd "$ROOT/apps/dearth_app" &&
        flutter build apk --release --split-per-abi --target-platform "$TARGET" --dart-define=DEARTH_VERSION="0.1.0-local.$sha" \
          --build-number="$(build_number "$APP_CODE")" >"$WORK/build.log" 2>&1) ||
        { tail -n 30 "$WORK/build.log" >&2; die "flutter build apk failed"; }
      NEW_APK="$ROOT/apps/dearth_app/build/app/outputs/flutter-apk/app-$ABI-release.apk" NEW_LABEL="local build $sha"
    fi
  else
    # The newest GitHub release's APK for this CPU (public repo: no token).
    curl -fsSL "https://api.github.com/repos/$DEARTH_REPO/releases/latest" -o "$WORK/release.json" ||
      die "couldn't read the latest release of $DEARTH_REPO"
    read -r TAG ASSET_URL ASSET_SHA < <(python3 - "$WORK/release.json" "$ABI" <<'PY'
import json, sys
release = json.load(open(sys.argv[1]))
for asset in release.get("assets", []):
    if asset["name"].endswith(f"-android-{sys.argv[2]}.apk"):
        digest = (asset.get("digest") or "").removeprefix("sha256:") or "-"
        print(release["tag_name"], asset["browser_download_url"], digest)
        break
else:
    print("- - -")
PY
    )
    [ -n "${TAG:-}" ] && [ "$TAG" != "-" ] || die "the latest release of $DEARTH_REPO has no $ABI APK"
    NEW_LABEL="$TAG"
    [ "$ASSET_SHA" = "-" ] || NEW_SHA="$ASSET_SHA"
    if [ $CHECK = 0 ] || [ -z "$NEW_SHA" ]; then
      NEW_APK="$CACHE/releases/$TAG/dearth-$ABI.apk"
      if [ ! -f "$NEW_APK" ]; then
        mkdir -p "$(dirname "$NEW_APK")"
        curl -fsSL "$ASSET_URL" -o "$NEW_APK.part" || die "couldn't download $ASSET_URL"
        mv "$NEW_APK.part" "$NEW_APK"
      fi
      [ -z "$NEW_SHA" ] || [ "$(sha256 "$NEW_APK")" = "$NEW_SHA" ] || { rm -f "$NEW_APK"; die "$TAG's APK doesn't match its published SHA-256"; }
    fi
  fi
  [ -z "$NEW_APK" ] || NEW_SHA=$(sha256 "$NEW_APK")

  if [ $CHECK = 1 ] && [ $BUILD = 1 ]; then
    ok "Installed: ${APP_HAVE:-nothing} (--build compares only when it installs)"
  elif [ -n "$APP_SHA" ] && [ "$APP_SHA" = "$NEW_SHA" ]; then
    ok "Dearth $APP_HAVE ($NEW_LABEL) is installed"
  elif [ $CHECK = 1 ]; then
    if [ -n "$APP_HAVE" ]; then differs "Dearth $APP_HAVE ($APP_CODE) is installed; $NEW_LABEL is available"; else differs "Dearth isn't installed; $NEW_LABEL is available"; fi
  else
    out=$(adb_ install -r "$NEW_APK" 2>&1 || true)
    case "$out" in
      *Success*) changed "Dearth ${APP_HAVE:+$APP_HAVE → }$NEW_LABEL installed"; INSTALLED=1 ;;
      *UPDATE_INCOMPATIBLE* | *"signatures do not match"* | *VERSION_DOWNGRADE*)
        # Android checks the version before the signature, so a downgrade
        # can hide a key mismatch too. Either way only a fresh install works.
        case "$out" in
          *VERSION_DOWNGRADE*) why="is a newer build ($APP_CODE)" ;;
          *) why="is signed with a different key" ;;
        esac
        if [ $REPLACE = 0 ]; then
          problem "The installed Dearth $why, so $NEW_LABEL can't update it in place."
          note "Run again with --replace to uninstall it first. That erases Dearth's data on this device (pairing included)."
        else
          adb_ uninstall "$APP" >/dev/null 2>&1 || true
          out=$(adb_ install "$NEW_APK" 2>&1 || true)
          case "$out" in
            *Success*) changed "Dearth replaced with $NEW_LABEL (its data on this device was reset)"; INSTALLED=1 ;;
            *) die "Dearth install failed: $out" ;;
          esac
        fi ;;
      *) die "Dearth install failed: $out" ;;
    esac
  fi
fi
APP_HAVE=$(sh_ dumpsys package "$APP" | sed -n 's/^ *versionName=//p' | head -n 1)

# ─────────────────────── FreeKiosk settings (Dearth) ───────────────────────

section "Kiosk"

# FreeKiosk keeps its settings in React Native's AsyncStorage (SQLite). Read
# them back as key=value lines; credentials are left out.
fk_settings() {
  [ $ROOT_SHELL = 1 ] || return 1
  local base="/data/data/$FK/databases/RKStorage" suffix
  for suffix in "" -wal -shm; do
    rm -f "$WORK/RKStorage$suffix"
    if [ "$(sh_ "[ -f $base$suffix ] && echo yes")" = yes ]; then
      adb_ exec-out cat "$base$suffix" >"$WORK/RKStorage$suffix" 2>/dev/null || return 1
    fi
  done
  python3 - "$WORK/RKStorage" <<'PY'
import sqlite3, sys
try:
    rows = sqlite3.connect(sys.argv[1]).execute("select key, value from catalystLocalStorage").fetchall()
except sqlite3.Error:
    sys.exit(1)
for key, value in rows:
    if any(word in key for word in ("pin", "api_key", "password", "token", "secret")):
        continue
    value = (value or "").strip()
    if len(value) >= 2 and value[0] == value[-1] == '"':
        value = value[1:-1]
    print(f"{key}={value}")
PY
}

# FreeKiosk's REST API key, shared with Dearth (SPEC §13.9): made once and
# kept on this computer, so later runs can check it.
FK_PORT=8080
KEY_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/dearth/freekiosk-${SERIAL%%:*}.key"
FK_KEY=""
[ ! -f "$KEY_FILE" ] || FK_KEY=$(tr -d ' \n' <"$KEY_FILE")
if [ -z "$FK_KEY" ] && [ $CHECK = 0 ]; then
  # Four groups of five letters and digits (~100 bits): short enough to type
  # on the frame once, if FreeKiosk holds on to an older key.
  FK_KEY=$(python3 -c 'import secrets, string; a = string.ascii_lowercase + string.digits; print("-".join("".join(secrets.choice(a) for _ in range(5)) for _ in range(4)))')
  mkdir -p "$(dirname "$KEY_FILE")"
  (umask 077 && printf '%s\n' "$FK_KEY" >"$KEY_FILE")
fi

# What FreeKiosk should hold: "storage key=value|what it means". A line
# without a meaning belongs to the line above it.
TAP_SECONDS=$(python3 -c "print(f'{$WINDOW / 1000:g}')")
FK_EXPECTED=(
  "@kiosk_enabled=true|Kiosk mode on"
  "@kiosk_display_mode=external_app|Locked to Dearth"
  "@kiosk_external_app_package=$APP|"
  "@kiosk_external_app_mode=single|"
  "@kiosk_auto_launch=true|Starts Dearth on boot"
  "@kiosk_auto_relaunch_app=true|Brings Dearth back if it exits or crashes"
  "@kiosk_back_button_mode=immediate|The Back button can't leave Dearth"
  "@kiosk_return_mode=button|Magic corner: $TAPS taps on the $CORNER corner within $TAP_SECONDS s, then the PIN"
  "@kiosk_return_button_position=$CORNER|"
  "@kiosk_return_tap_count=$TAPS|"
  "@kiosk_return_tap_timeout=$WINDOW|"
  "@kiosk_overlay_button_visible=false|"
  "@kiosk_volume_up_5tap_enabled=false|The volume buttons change the volume"
  "@kiosk_keep_screen_on=true|Screen stays on"
  "@brightness_management_enabled=false|Brightness left to Android (adaptive)"
  "@kiosk_auto_brightness_enabled=false|"
  "@screensaver_enabled=false|FreeKiosk's screensaver off (Dearth has its own)"
  "@kiosk_rest_api_enabled=true|FreeKiosk's REST API on port $FK_PORT (Dearth turns the screen off through it)"
  "@kiosk_rest_api_port=$FK_PORT|"
  "@kiosk_allow_notifications=false|No notification shade or status bar"
  "@kiosk_allow_system_info=false|"
  "@kiosk_status_bar_enabled=false|"
)
# The same settings as ADB config extras (FreeKiosk docs: adb-configuration.md).
FK_EXTRAS=(
  --es pin "$PIN" --es lock_package "$APP" --es display_mode external_app --es external_app_mode single
  --es kiosk_enabled true --es auto_launch true --es auto_relaunch true --es back_button_mode immediate
  --es return_mode button --es return_button_position "$CORNER" --es return_tap_count "$TAPS"
  --es return_tap_timeout "$WINDOW" --es overlay_button_visible false --es volume_up_5tap_enabled false
  --es keep_screen_on true --es brightness_management_enabled false --es auto_brightness_enabled false
  --es screensaver_enabled false --es allow_notifications false --es allow_system_info false
  --es status_bar_enabled false --ez auto_start true
  --es rest_api_enabled true --es rest_api_port "$FK_PORT"
)
# FreeKiosk only takes a key over ADB while it holds none (it keeps the first
# one it was given), so sending it on every push is harmless.
[ -z "$FK_KEY" ] || FK_EXTRAS+=(--es rest_api_key "$FK_KEY")

# `fk_compare <settings file> <report>`: prints each meaning with ✓ or ✗
# when <report> is 1; returns 1 if anything differs.
fk_compare() {
  local file=$1 report=$2 entry key want what have group="" group_ok=1 all_ok=0
  flush() {
    [ -n "$group" ] || return 0
    if [ "$report" = 1 ]; then
      if [ $group_ok = 1 ]; then ok "$group"; elif [ $CHECK = 1 ]; then differs "$group"; fi
    fi
    [ $group_ok = 1 ] || all_ok=1
  }
  for entry in "${FK_EXPECTED[@]}"; do
    key=${entry%%=*} want=${entry#*=} what=${want#*|} want=${want%%|*}
    if [ -n "$what" ]; then flush; group=$what group_ok=1; fi
    have=$(sed -n "s/^$key=//p" "$file" | head -n 1)
    [ "$have" = "$want" ] || group_ok=0
  done
  flush
  return $all_ok
}

# Sends the settings and waits for FreeKiosk to restart with them (it
# broadcasts SETTINGS_LOADED, then EXTERNAL_APP_LAUNCHED once Dearth is up).
fk_push() {
  local log="$WORK/freekiosk.log" result=timeout
  adb_ logcat -c >/dev/null 2>&1 || true
  adb_ logcat -v brief -s FreeKiosk-ADB >"$log" 2>/dev/null &
  LOGCAT_PID=$!
  adb_ shell am start -n "$FK/.MainActivity" "${FK_EXTRAS[@]}" >/dev/null 2>&1 || true
  for _ in $(seq 1 60); do
    if grep -q "EXTERNAL_APP_LAUNCHED" "$log"; then result=ok; break; fi
    if grep -qiE "invalid pin|pin required|incorrect pin" "$log"; then result=pin; break; fi
    sleep 1
  done
  kill "$LOGCAT_PID" 2>/dev/null || true
  wait "$LOGCAT_PID" 2>/dev/null || true
  LOGCAT_PID=""
  printf '%s' "$result"
}

PUSHED=0
if fk_settings >"$WORK/fk.txt"; then
  if fk_compare "$WORK/fk.txt" 1; then
    :
  elif [ $CHECK = 0 ]; then
    result=$(fk_push)
    PUSHED=1
    [ "$result" != pin ] || die "FreeKiosk refused the PIN. Pass the device's current one with --pin"
    if fk_settings >"$WORK/fk.txt" && fk_compare "$WORK/fk.txt" 0; then
      changed "Kiosk settings applied (FreeKiosk restarted with Dearth in front)"
    else
      problem "FreeKiosk didn't take every setting (wrong --pin?). Check: adb -s $SERIAL logcat -s FreeKiosk-ADB"
    fi
  fi
elif [ $CHECK = 1 ]; then
  note "Can't read FreeKiosk's settings back without a root ADB shell"
else
  [ "$(fk_push)" != pin ] || die "FreeKiosk refused the PIN. Pass the device's current one with --pin"
  PUSHED=1
  changed "Kiosk settings sent (no root shell to read them back)"
fi

# The magic corner is FreeKiosk's overlay window: a button-sized square at the
# corner. Tap-anywhere mode uses a 1×1 window instead, and none at all means
# FreeKiosk can't draw over apps. Prints "<width>x<height>" of that window.
corner_window() {
  sh_ dumpsys window windows | awk '
    function report() {
      if (block ~ /ty=APPLICATION_OVERLAY/ && block ~ /freekiosk/ && split(frame, n, /[^0-9]+/) >= 5) { print (n[4] - n[2]) "x" (n[5] - n[3]); found = 1; exit }
    }
    /^  Window #/ { report(); block = $0; frame = ""; next }
    { block = block "\n" $0 }
    /mFrame=/ { frame = $0; sub(/.*mFrame=/, "", frame); sub(/ .*/, "", frame) }
    END { if (!found) report() }'
}
# FreeKiosk ≤ 2.0.0-beta.4 can start its overlay with the settings it had
# before the restart; a second send makes it start with the new ones.
corner_live() {
  local size
  for _ in $(seq 1 15); do
    size=$(corner_window)
    if [ -n "$size" ] && [ "${size%%x*}" -gt 10 ]; then return 0; fi
    sleep 1
  done
  return 1
}
if [[ "$(sh_ appops get "$FK" SYSTEM_ALERT_WINDOW)" != *allow* ]]; then
  [ $CHECK = 1 ] || problem "The magic corner can't appear: FreeKiosk may not display over other apps"
elif corner_live; then
  ok "Magic corner is on screen ($(corner_window) px, $CORNER)"
elif [ $CHECK = 1 ]; then
  differs "The magic corner isn't on screen (FreeKiosk shows it after its next start)"
else
  [ "$(fk_push)" != pin ] || die "FreeKiosk refused the PIN. Pass the device's current one with --pin"
  PUSHED=1
  if corner_live; then changed "Magic corner on screen ($(corner_window) px, $CORNER)"; else problem "The magic corner still isn't on screen. Try --reboot"; fi
fi
# Uninstalling Dearth also prunes it from the Device Owner's lock-task list,
# and FreeKiosk can't launch an app that isn't on the list: the frame sits on
# "waiting for application" forever, and a bare `am start` is refused with a
# lock-task mode violation. Sending the settings again makes FreeKiosk
# rebuild the list and launch Dearth.
if [ $ROOT_SHELL = 1 ] && [ -n "$(sh_ pm path "$APP")" ] && [[ "$(sh_ cat /data/system/device_policies.xml)" != *"\"$APP\""* ]]; then
  if [ $CHECK = 1 ]; then
    differs "Dearth isn't on the lock-task list: FreeKiosk couldn't start it"
  elif [ $PUSHED = 0 ]; then
    [ "$(fk_push)" != pin ] || die "FreeKiosk refused the PIN. Pass the device's current one with --pin"
    PUSHED=1
    changed "Dearth back on the lock-task list (an uninstall prunes it)"
  fi
fi
# A fresh install also stops Dearth; when no settings went out this run,
# FreeKiosk relaunches it by itself, but don't wait on that.
if [ $INSTALLED = 1 ] && [ $PUSHED = 0 ]; then
  sh_ am start -n "$APP/.MainActivity" >/dev/null
fi

# ─────────────────────────── FreeKiosk bridge ──────────────────────────────

section "Bridge"
fk_answers() { curl -fs -m 5 -H "X-Api-Key: $FK_KEY" "http://${SERIAL%%:*}:$FK_PORT/api/health" 2>/dev/null | grep -q '"status":"ok"'; }
if [ -z "$FK_KEY" ]; then
  differs "No FreeKiosk key on this computer yet ($KEY_FILE)"
elif fk_answers; then
  ok "FreeKiosk's REST API answers to Dearth's key"
elif [ $CHECK = 1 ]; then
  differs "FreeKiosk's REST API doesn't answer to the key in $KEY_FILE"
else
  # Not pushed this run (the settings matched): push once more with the key.
  if [ $PUSHED = 0 ]; then
    [ "$(fk_push)" != pin ] || die "FreeKiosk refused the PIN. Pass the device's current one with --pin"
    PUSHED=1
  fi
  for _ in $(seq 1 10); do fk_answers && break; sleep 2; done
  if fk_answers; then
    changed "FreeKiosk's REST API answers to Dearth's key"
  else
    problem "FreeKiosk keeps an older REST API key and ignores new ones sent over ADB. Once, on the frame: tap the $CORNER corner $TAPS times, enter the PIN, open Advanced → REST API, set the API key to  $FK_KEY  and save. Then run this again."
  fi
fi
# FreeKiosk's boot screen can stick when the network sets the clock while
# it's up (the frame boots at 1970); Dearth brings it back after a boot,
# which takes starting an activity from the background (KioskWatch).
[ -z "$(sh_ pm path "$APP")" ] || appop SYSTEM_ALERT_WINDOW "Dearth can unstick FreeKiosk's boot screen" "$APP"
# Dearth learns the key when brought to the front with it, and keeps it.
if [ -n "$FK_KEY" ] && [ -n "$(sh_ pm path "$APP")" ]; then
  if [ $CHECK = 1 ]; then
    note "Dearth is handed the key on every run (it can't be read back)"
  else
    adb_ shell am start -n "$APP/.MainActivity" --es freekiosk_api_key "$FK_KEY" --ei freekiosk_port "$FK_PORT" >/dev/null 2>&1 || true
    ok "Dearth has the key (Settings → Screen & sound → Kiosk shows whether it works)"
  fi
fi
# Joining a Hub: the app claims the code itself and answers on logcat
# (frame_tool.dart, as for tool/perf_gate.sh).
if [ -n "$JOIN_CODE" ] && [ -n "$(sh_ pm path "$APP")" ]; then
  if [ $CHECK = 1 ]; then
    note "--join is skipped with --check"
  else
    adb_ logcat -c 2>/dev/null || true
    adb_ shell am start -n "$APP/.MainActivity" --es dearth_hub "$JOIN_HUB" --es dearth_enroll "$JOIN_CODE" >/dev/null 2>&1 || true
    joined=""
    for _ in $(seq 1 45); do
      joined=$(adb_ logcat -d -v raw -s DearthTool:I 2>/dev/null | tr -d '\r' | sed -n 's/^DEARTH_TOOL enroll //p' | tail -n 1)
      [ -n "$joined" ] && break
      sleep 1
    done
    case "$joined" in
      '') problem "Dearth didn't answer the join (a build from before 2026-10-10 can't): enter the code on its onboarding screen" ;;
      *'"error"'*) problem "Dearth didn't join $JOIN_HUB: $(printf '%s' "$joined" | python3 -I -c 'import json,sys; print(json.load(sys.stdin)["error"])')" ;;
      *) changed "Dearth joined the Hub at $JOIN_HUB" ;;
    esac
  fi
fi

# ─────────────────────────────── Android ───────────────────────────────────

# After FreeKiosk: when it restarts with brightness management off, it puts
# back the brightness mode it found the first time, once.
section "Display"
setting system accelerometer_rotation 1 "Auto-rotate"
# Vendor ROMs like the JT215M's restore auto-rotate from this property at
# every boot, whatever the setting says. Dearth follows the accelerometer on
# wall displays either way; this keeps FreeKiosk's own screens turning too.
autorotation=$(sh_ getprop persist.sys.autorotation)
if [ -n "$autorotation" ]; then
  if [ "$autorotation" = 1 ]; then
    ok "Auto-rotate stays on after a reboot"
  elif [ $CHECK = 1 ]; then
    differs "Auto-rotate turns off again at every boot (persist.sys.autorotation is $autorotation)"
  else
    sh_ setprop persist.sys.autorotation 1 >/dev/null
    if [ "$(sh_ getprop persist.sys.autorotation)" = 1 ]; then changed "Auto-rotate stays on after a reboot"; else problem "couldn't set persist.sys.autorotation (it needs a root shell)"; fi
  fi
fi
setting system screen_brightness_mode 1 "Adaptive brightness: dims with the room's light"
setting system screen_off_timeout 2147483647 "Screen never times out"
setting secure screensaver_enabled 0 "Android's screensaver off"
if [ "$(sh_ locksettings get-disabled)" = true ]; then
  ok "No lock screen"
elif [ $CHECK = 1 ]; then
  differs "Lock screen is on"
else
  sh_ locksettings set-disabled true >/dev/null
  changed "Lock screen off"
fi
# The vendor status bar refuses to die under lock task: it hangs over Dearth
# as an empty strip unless the app hides the bars itself, and older builds
# didn't. policy_control forces Dearth full screen whatever the build.
setting global policy_control immersive.full="$APP" "No status-bar strip over Dearth"
if [ -n "$DENSITY" ]; then
  density=$(sh_ wm density | sed -n 's/^Override density: //p')
  if [ "$density" = "$DENSITY" ]; then
    ok "Density $DENSITY"
  elif [ $CHECK = 1 ]; then
    differs "Density is ${density:-the default}, should be $DENSITY"
  else
    sh_ wm density "$DENSITY" >/dev/null
    changed "Density $DENSITY"
  fi
fi
if [ -n "$ANIMATION" ]; then
  scales="window_animation_scale transition_animation_scale animator_duration_scale" same=1
  for key in $scales; do [ "$(sh_ settings get global "$key")" = "$ANIMATION" ] || same=0; done
  if [ $same = 1 ]; then
    ok "System animations at ${ANIMATION}×"
  elif [ $CHECK = 1 ]; then
    differs "System animations aren't at ${ANIMATION}×"
  else
    for key in $scales; do sh_ settings put global "$key" "$ANIMATION" >/dev/null; done
    changed "System animations at ${ANIMATION}×"
  fi
fi

section "System"
setting global wifi_sleep_policy 2 "Wi-Fi stays on"
setting global auto_time 1 "Time from the network"
if [ -n "$TZ_WANT" ]; then
  tz=$(sh_ getprop persist.sys.timezone)
  if [ "$tz" = "$TZ_WANT" ]; then
    ok "Time zone $tz"
  elif [ $CHECK = 1 ]; then
    differs "Time zone is $tz, should be $TZ_WANT"
  else
    sh_ settings put global auto_time_zone 0 >/dev/null
    sh_ service call alarm 3 s16 "$TZ_WANT" >/dev/null # IAlarmManager.setTimeZone
    if [ "$(sh_ getprop persist.sys.timezone)" = "$TZ_WANT" ]; then changed "Time zone $tz → $TZ_WANT"; else problem "couldn't set the time zone to $TZ_WANT"; fi
  fi
fi
# Exempt from Doze, so sync and the kiosk keep running while the screen is off.
for pkg in "$APP" "$FK"; do
  [ -n "$(sh_ pm path "$pkg")" ] || continue
  if [[ "$(sh_ dumpsys deviceidle whitelist)" == *",$pkg,"* ]]; then
    ok "$pkg exempt from battery optimization"
  elif [ $CHECK = 1 ]; then
    differs "$pkg isn't exempt from battery optimization"
  else
    sh_ dumpsys deviceidle whitelist "+$pkg" >/dev/null
    changed "$pkg exempt from battery optimization"
  fi
done
# Reminders and kitchen timers chime on the media stream.
volume=$(sh_ media volume --stream 3 --get | sed -n 's/.*volume is \([0-9]*\) in range \[0\.\.\([0-9]*\)\].*/\1 \2/p')
if [ -n "$volume" ]; then
  read -r level max <<<"$volume"
  if [ "$level" -gt 0 ]; then
    ok "Media volume $level/$max (chimes and timers)"
  elif [ $CHECK = 1 ]; then
    differs "Media volume is muted: reminders and timers would be silent"
  else
    sh_ media volume --stream 3 --set $((max * 2 / 3)) >/dev/null
    changed "Media volume $((max * 2 / 3))/$max (was muted)"
  fi
fi

if [ -n "$VENDOR_APPS" ] && [ $BLOAT = 1 ]; then
  section "Vendor apps"
  disabled=$'\n'$(sh_ pm list packages -d)$'\n'
  installed=$'\n'$(sh_ pm list packages)$'\n'
  off=0 now=0
  for pkg in $VENDOR_APPS; do
    [[ "$installed" == *$'\n'"package:$pkg"$'\n'* ]] || continue
    if [[ "$disabled" == *$'\n'"package:$pkg"$'\n'* ]]; then
      off=$((off + 1))
    elif [ $CHECK = 1 ]; then
      differs "$pkg is enabled"
    else
      [[ "$(sh_ pm disable-user --user 0 "$pkg")" == *disabled* ]] && now=$((now + 1)) || problem "couldn't disable $pkg"
    fi
  done
  [ $off = 0 ] || ok "$off vendor apps disabled"
  [ $now = 0 ] || changed "$now more vendor apps disabled"
  if [[ "$disabled" == *$'\n'"package:com.waophoto.fota"$'\n'* ]]; then
    if [ $CHECK = 1 ]; then differs "com.waophoto.fota is disabled: every app crash-loops"; else sh_ pm enable com.waophoto.fota >/dev/null; changed "com.waophoto.fota enabled again (it must stay on)"; fi
  fi
fi

# ─────────────────────────────── WebView ───────────────────────────────────

section "WebView"
webview=$(sh_ dumpsys webviewupdate | sed -n 's/.*Current WebView package (name, version): (\([^,]*\), \([0-9.]*\)).*/\1 \2/p' | head -n 1)
read -r WV_PKG WV_VERSION <<<"${webview:-unknown 0}"
if [ "${WV_VERSION%%.*}" -ge 111 ] 2>/dev/null; then
  ok "System WebView $WV_VERSION"
elif [ $WEBVIEW = 0 ]; then
  note "System WebView is ${WV_VERSION:-unknown}: add --webview before Dearth embeds YouTube"
elif [ $CHECK = 1 ]; then
  differs "System WebView is ${WV_VERSION:-unknown}"
else
  # The newest arm32 com.android.webview is AOSP's android15-release prebuilt
  # (Chromium 124, minSdk 26). Vendor test-keys ROMs only accept their own
  # certificate for it: AOSP's public test key, published with the source.
  [ "$ABI" = armeabi-v7a ] || die "--webview only knows the arm32 AOSP WebView"
  APKSIGNER=$(command -v apksigner || ls -d "${ANDROID_HOME:-/opt/android-sdk}"/build-tools/*/apksigner 2>/dev/null | sort -V | tail -n 1 || true)
  [ -n "$APKSIGNER" ] || die "--webview needs apksigner (Android SDK build-tools)"
  dir="$CACHE/webview-124"
  mkdir -p "$dir"
  if [ ! -f "$dir/webview-signed.apk" ]; then
    curl -fsSL "https://android.googlesource.com/platform/external/chromium-webview/+/refs/heads/android15-release/prebuilt/arm/webview.apk?format=TEXT" | base64 -d >"$dir/webview.apk"
    curl -fsSL "https://android.googlesource.com/platform/build/+/refs/heads/main/target/product/security/testkey.pk8?format=TEXT" | base64 -d >"$dir/testkey.pk8"
    curl -fsSL "https://android.googlesource.com/platform/build/+/refs/heads/main/target/product/security/testkey.x509.pem?format=TEXT" | base64 -d >"$dir/testkey.x509.pem"
    "$APKSIGNER" sign --key "$dir/testkey.pk8" --cert "$dir/testkey.x509.pem" --out "$dir/webview-signed.apk" "$dir/webview.apk"
  fi
  out=$(adb_ install -r "$dir/webview-signed.apk" 2>&1 || true)
  case "$out" in
    *Success*) changed "System WebView 124 installed (active after a reboot)"; REBOOT=1 ;;
    *) problem "WebView install failed (the ROM's WebView isn't signed with the AOSP test key?): $out" ;;
  esac
fi

# ──────────────────────────────── reboot ───────────────────────────────────

focus() { sh_ dumpsys window | sed -n 's/.*mCurrentFocus=Window{[^ ]* [^ ]* \([^/} ]*\).*/\1/p' | head -n 1; }
if [ $REBOOT = 1 ] && [ $CHECK = 0 ]; then
  section "Reboot"
  adb_ reboot >/dev/null 2>&1 || true
  note "Waiting for the device to come back…"
  for _ in $(seq 1 90); do
    "$ADB" connect "$SERIAL" >/dev/null 2>&1 || true
    [ "$(sh_ getprop sys.boot_completed)" = 1 ] && break
    sleep 2
  done
  [ "$(sh_ getprop sys.boot_completed)" = 1 ] || die "the device didn't come back within 3 minutes"
  # Up to four minutes: when FreeKiosk's boot screen sticks (the clock jumps
  # from 1970 while it's up), Dearth brings it back two minutes after boot.
  for _ in $(seq 1 120); do
    [ "$(focus)" = "$APP" ] && break
    sleep 2
  done
  if [ "$(focus)" = "$APP" ]; then
    ok "Dearth came back by itself after the reboot"
  elif sh_ dumpsys window | grep -q "mCurrentFocus=.*BootLockActivity"; then
    problem "FreeKiosk's boot screen is stuck (\"Starting kiosk…\") and Dearth didn't bring it back. Unstick it: adb -s $SERIAL shell am start -n $FK/.MainActivity"
  else
    problem "After the reboot, $(focus) is in front, not Dearth"
  fi
  setting system accelerometer_rotation 1 "Auto-rotate still on"
  setting system screen_brightness_mode 1 "Adaptive brightness still on"
fi

# ─────────────────────────────── summary ───────────────────────────────────

section "Summary"
front=$(focus)
[ "$front" = "$APP" ] && ok "Dearth ${APP_HAVE:-} is in front" || note "In front now: ${front:-unknown}"
note "Back to FreeKiosk: tap the $CORNER corner $TAPS times within $TAP_SECONDS s, then the PIN."
if [ $CHECK = 1 ]; then
  if [ $((DIFFS + PROBLEMS)) = 0 ]; then ok "Everything is set up"; exit 0; fi
  printf '  %d difference(s). Run without --check to fix them.\n' $((DIFFS + PROBLEMS))
  exit 1
fi
[ $PROBLEMS = 0 ] || { printf '  %s%d problem(s) need a look (above).%s\n' "$RED" "$PROBLEMS" "$OFF"; exit 1; }
[ $CHANGES = 0 ] && ok "Already set up; nothing changed" || ok "$CHANGES change(s) made"
