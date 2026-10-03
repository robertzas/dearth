#!/usr/bin/env bash
# Builds every target this host can build into dist/ (SPEC §16.2). iOS,
# macOS and Windows build on their own runners in CI
# (.github/workflows/build.yml).
#
#   tool/build_all.sh                 # web + linux + android + hub
#   tool/build_all.sh web hub         # just these
#   tool/build_all.sh --hub-image     # also the Hub Docker image (dearth-hub:dev)
#
# Targets: web, linux, android, hub. Outputs are named
# dearth-<version>-<target>.* like the GitHub release assets.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/apps/dearth_app"
DIST="$ROOT/dist"
VERSION="$(sed -n 's/^version: *\([0-9.]*\).*/\1/p' "$APP/pubspec.yaml")-local"

targets=()
IMAGE=0
for arg in "$@"; do
  case "$arg" in
    --hub-image) IMAGE=1 ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    web|linux|android|hub) targets+=("$arg") ;;
    *) echo "unknown target: $arg" >&2; exit 2 ;;
  esac
done
[[ ${#targets[@]} -eq 0 ]] && targets=(web linux android hub)

step() { printf '\n\033[1;34m▶ %s\033[0m\n' "$*"; }
want() { [[ " ${targets[*]} " == *" $1 "* ]]; }
mkdir -p "$DIST"
cd "$ROOT" && flutter pub get >/dev/null
DEFINES=(--dart-define=DEARTH_VERSION="$VERSION")

if want web || want hub || [[ $IMAGE -eq 1 ]]; then
  step "Web"
  "$ROOT/tool/web_assets.sh"
  (cd "$APP" && flutter build web --release --no-wasm-dry-run "${DEFINES[@]}")
  rm -rf "$DIST/web" && cp -r "$APP/build/web" "$DIST/web"
  (cd "$DIST/web" && rm -f "$DIST/dearth-$VERSION-web.zip" && zip -qr "$DIST/dearth-$VERSION-web.zip" .)
fi

if want linux; then
  step "Linux desktop"
  (cd "$APP" && flutter build linux --release "${DEFINES[@]}")
  tar -czf "$DIST/dearth-$VERSION-linux-x64.tar.gz" -C "$APP/build/linux/x64/release/bundle" .
fi

if want android; then
  if [[ -z "${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}" ]]; then
    echo "Skipping Android: no ANDROID_HOME" >&2
  else
    step "Android APKs (armeabi-v7a for the frame, arm64-v8a, x86_64)"
    (cd "$APP" && flutter build apk --release --split-per-abi --target-platform android-arm,android-arm64,android-x64 "${DEFINES[@]}")
    for abi in armeabi-v7a arm64-v8a x86_64; do
      cp "$APP/build/app/outputs/flutter-apk/app-$abi-release.apk" "$DIST/dearth-$VERSION-android-$abi.apk"
    done
  fi
fi

if want hub; then
  step "Hub bundle (binary + web app)"
  out="$ROOT/tool/.work/hub-build"
  rm -rf "$out" && (cd "$ROOT/hub/dearth_hub" && dart build cli -o "$out")
  cp -r "$DIST/web" "$out/bundle/web"
  cp "$ROOT/LICENSE" "$ROOT/compose.yml" "$ROOT/.env.example" "$out/bundle/"
  tar -czf "$DIST/dearth-hub-$VERSION-linux-$(uname -m).tar.gz" -C "$out/bundle" .
fi

if [[ $IMAGE -eq 1 ]]; then
  step "Hub image"
  docker build --build-arg VERSION="$VERSION" -t dearth-hub:dev "$ROOT"
fi

printf '\n\033[1;32mBuilt into %s:\033[0m\n' "$DIST"
ls -1 "$DIST" | grep -v '^web$' | sed 's/^/  /'
