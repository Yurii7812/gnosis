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
for root in (repo / "assets", out):
    sym = (root / "icons" / "gnosis-symbol.svg").read_text()
    ET.fromstring(sym)
    assert 'fill="#14283D"' in sym, root
    assert 'fill="#79CFFF"' in sym, root
    logo = (root / "logo" / "gnosis-logo.svg").read_text()
    ET.fromstring(logo)
    assert 'fill="#79CFFF"' in logo, root
print("OK: SVG palette #14283D / #79CFFF")
try:
    from PIL import Image
except ImportError:
    print("OK: Pillow unavailable: SVG-only icon build supported")
else:
    im = Image.open(out / "icons" / "gnosis-256.png").convert("RGB")
    assert im.getpixel((3, 128)) == (20, 40, 61), im.getpixel((3, 128))
    print("OK: generated PNG palette matches SVG")
PY
echo 'icon palette OK'
