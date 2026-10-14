#!/bin/sh
# Gnosis 起動画面パレットにSVG/PNGが一致することを検査
set -eu
REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
GNOSIS_ICON_OUTPUT_ROOT="$WORK/out" python3 "$REPO/tools/build_icons.py" > "$WORK/build.log" 2>&1
python3 - "$REPO" "$WORK/out" <<'PY'
from pathlib import Path
import sys
import xml.etree.ElementTree as ET
repo, out = map(Path, sys.argv[1:])
for root in (out,):
    sym = (root / "icons" / "gnosis-symbol.svg").read_text()
    ET.fromstring(sym)
    assert 'fill="#234566"' in sym, root
    assert 'fill="#FFFFFF"' in sym, root
    logo = (root / "logo" / "gnosis-logo.svg").read_text()
    ET.fromstring(logo)
    assert 'fill="#D7F8FF"' in logo, root
print("OK: SVG palette #234566 tile / #FFFFFF ink")
try:
    from PIL import Image
except ImportError:
    print("OK: Pillow unavailable: SVG-only icon build supported")
else:
    im = Image.open(out / "icons" / "gnosis-256.png").convert("RGB")
    assert im.getpixel((3, 128)) == (35, 69, 102), im.getpixel((3, 128))
    print("OK: generated PNG palette matches SVG")
PY
echo 'icon palette OK'
