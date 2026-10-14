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
    assert 'fill="#071827"' in sym, root
    assert 'fill="#D7F8FF"' in sym, root
    logo = (root / "logo" / "gnosis-logo.svg").read_text()
    ET.fromstring(logo)
    assert 'fill="#D7F8FF"' in logo, root
print("OK: SVG palette #071827 / #D7F8FF")
try:
    from PIL import Image
except ImportError:
    print("OK: Pillow unavailable: SVG-only icon build supported")
else:
    im = Image.open(out / "icons" / "gnosis-256.png").convert("RGB")
    assert im.getpixel((3, 128)) == (7, 24, 39), im.getpixel((3, 128))
    print("OK: generated PNG palette matches SVG")
PY
echo 'icon palette OK'
