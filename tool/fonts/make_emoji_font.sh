#!/usr/bin/env bash
# Builds packages/dearth_ui/assets/fonts/DearthEmoji.ttf: the emoji that
# Android 10's system font (the kitchen frame's) can't draw, taken from
# Google's current Noto Color Emoji (OFL). The app falls back to it after
# the system emoji font (DFonts.emoji), so 🪥, 🪴, 🛝, 🫙 and the rest of
# Emoji 13+ show as pictures instead of empty boxes there.
#
# Only single code points go in (no skin tones or ZWJ sequences): that
# keeps the font about 340 KB. Both sources are pinned by SHA-256.
# Requires curl and fonttools (pyftsubset). The output is tracked with
# Git LFS.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT="$ROOT/packages/dearth_ui/assets/fonts/DearthEmoji.ttf"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

NEW_URL="https://raw.githubusercontent.com/googlefonts/noto-emoji/1ffdd21391dd1f25c081fa93a9dea0c7c029442b/2D/fonts/NotoColorEmoji.ttf"
NEW_SHA="15671215ab769fdc7162a045d56fd7d7e477c51b04e6b3c761d914d8fdd6cc44"
# Android 10's emoji font, byte for byte what /system/fonts holds on the frame.
OLD_URL="https://android.googlesource.com/platform/external/noto-fonts/+/refs/heads/android10-release/emoji/NotoColorEmoji.ttf?format=TEXT"
OLD_SHA="6c1cb254a0ca8272f146bb70400750227664740f1fa1d732aef56a1bb9a62782"

curl -fsSL "$NEW_URL" -o "$TMP/new.ttf"
curl -fsSL "$OLD_URL" | base64 -d > "$TMP/old.ttf"
echo "$NEW_SHA  $TMP/new.ttf" | sha256sum -c --quiet
echo "$OLD_SHA  $TMP/old.ttf" | sha256sum -c --quiet

python3 -I - "$TMP/new.ttf" "$TMP/old.ttf" "$TMP/unicodes.txt" <<'EOF'
import sys
from fontTools.ttLib import TTFont
new = TTFont(sys.argv[1]).getBestCmap()
old = TTFont(sys.argv[2]).getBestCmap()
# Emoji only: skip the spaces, joiners and selectors both fonts map.
missing = sorted(c for c in new if c not in old and c >= 0x2000)
open(sys.argv[3], 'w').write(','.join('%X' % c for c in missing))
print(f'{len(missing)} emoji missing from Android 10')
EOF

pyftsubset "$TMP/new.ttf" --unicodes-file="$TMP/unicodes.txt" --layout-features='' --no-layout-closure --output-file="$TMP/sub.ttf"

# A subset is a modified font: rename it (OFL §3) so nothing mistakes it for
# the full Noto Color Emoji.
python3 -I - "$TMP/sub.ttf" "$OUT" <<'EOF'
import sys
from fontTools.ttLib import TTFont
f = TTFont(sys.argv[1])
name = f['name']
for rec in list(name.names):
    if rec.nameID in (1, 3, 4, 6, 16, 17, 21, 22):
        name.removeNames(nameID=rec.nameID)
for nid, value in ((1, 'Dearth Emoji'), (3, 'Dearth Emoji (subset of Noto Color Emoji)'), (4, 'Dearth Emoji'), (6, 'DearthEmoji')):
    name.setName(value, nid, 3, 1, 0x409)
f.save(sys.argv[2])
EOF
ls -l "$OUT"
