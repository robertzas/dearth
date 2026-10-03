#!/usr/bin/env bash
# Renders the app icon (tool/icons/dearth_icon.svg) for every platform.
# Requires rsvg-convert and ImageMagick. Outputs are tracked with Git LFS.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP="$ROOT/apps/dearth_app"
SVG="$ROOT/tool/icons/dearth_icon.svg"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

square() { rsvg-convert -w "$1" -h "$1" "$SVG" -o "$2"; }
# Rounded variant with transparent corners (radius ≈ 22.5 %).
rounded() {
  local s=$1 out=$2 r
  r=$(( s * 225 / 1000 ))
  square "$s" "$TMP/sq.png"
  magick -size "${s}x${s}" xc:none -fill white -draw "roundrectangle 0,0,$((s-1)),$((s-1)),$r,$r" "$TMP/mask.png"
  magick "$TMP/sq.png" "$TMP/mask.png" -alpha off -compose CopyOpacity -composite "$out"
}
# macOS: rounded body at 80 % with a soft shadow on a transparent canvas.
macos() {
  local s=$1 out=$2 body
  body=$(( s * 824 / 1024 ))
  rounded "$body" "$TMP/body.png"
  magick -size "${s}x${s}" xc:none \( "$TMP/body.png" -background none -shadow 40x$(( s / 64 + 1 ))+0+$(( s / 100 )) \) -gravity center -composite \
    "$TMP/body.png" -gravity center -composite "$out"
}

# Android launcher icons (legacy, rounded).
for d in mdpi:48 hdpi:72 xhdpi:96 xxhdpi:144 xxxhdpi:192; do
  rounded "${d#*:}" "$APP/android/app/src/main/res/mipmap-${d%%:*}/ic_launcher.png"
done

# iOS (opaque squares; the system applies the mask).
IOS="$APP/ios/Runner/Assets.xcassets/AppIcon.appiconset"
for spec in 20x20@1x:20 20x20@2x:40 20x20@3x:60 29x29@1x:29 29x29@2x:58 29x29@3x:87 40x40@1x:40 40x40@2x:80 40x40@3x:120 \
            60x60@2x:120 60x60@3x:180 76x76@1x:76 76x76@2x:152 83.5x83.5@2x:167 1024x1024@1x:1024; do
  square "${spec#*:}" "$TMP/ios.png"
  magick "$TMP/ios.png" -background '#4646BE' -alpha remove -alpha off "$IOS/Icon-App-${spec%%:*}.png"
done

# macOS.
MAC="$APP/macos/Runner/Assets.xcassets/AppIcon.appiconset"
for s in 16 32 64 128 256 512 1024; do macos "$s" "$MAC/app_icon_$s.png"; done

# Web: favicon, PWA icons, maskable (full bleed).
rounded 64 "$APP/web/favicon.png"
rounded 192 "$APP/web/icons/Icon-192.png"
rounded 512 "$APP/web/icons/Icon-512.png"
square 192 "$APP/web/icons/Icon-maskable-192.png"
square 512 "$APP/web/icons/Icon-maskable-512.png"

# Windows .ico (multi-resolution).
for s in 16 24 32 48 64 128 256; do rounded "$s" "$TMP/win-$s.png"; done
magick "$TMP"/win-{16,24,32,48,64,128,256}.png "$APP/windows/runner/resources/app_icon.ico"

# iOS launch image: brand color background (plain, Flutter shows the splash).
for f in LaunchImage LaunchImage@2x LaunchImage@3x; do
  magick -size 1x1 xc:'#F7F4EE' "$APP/ios/Runner/Assets.xcassets/LaunchImage.imageset/$f.png"
done
echo "icons written"
