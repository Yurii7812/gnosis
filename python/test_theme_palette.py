#!/usr/bin/env python3
"""標準テーマ（assets/themes/builtin.json）の色が、配色エディタのカラーパレット（8 色相 × 9 段階）の色だけで作られている。"""
import json
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
HUES = [(0, 0.0), (0, 0.62), (28, 0.72), (50, 0.78), (130, 0.45), (175, 0.5), (212, 0.62), (275, 0.45)]
LIGHTS = [0.12, 0.22, 0.34, 0.46, 0.58, 0.70, 0.82, 0.92, 0.98]


def hsl2hex(h, s, l):
    if s <= 0:
        r = g = b = l
    else:
        q = l * (1 + s) if l < 0.5 else l + s - l * s
        p = 2 * l - q

        def f(t):
            t %= 1
            if t < 1 / 6:
                return p + (q - p) * 6 * t
            if t < 0.5:
                return q
            if t < 2 / 3:
                return p + (q - p) * (2 / 3 - t) * 6
            return p
        h /= 360
        r, g, b = f(h + 1 / 3), f(h), f(h - 1 / 3)
    return "#%02x%02x%02x" % tuple(int(x * 255 + 0.5) for x in (r, g, b))


palette = {hsl2hex(h, s, l) for h, s in HUES for l in LIGHTS}
themes = json.loads((REPO / "assets/themes/builtin.json").read_text(encoding="utf-8"))
ng = 0
for name, t in themes.items():
    for key, val in t.items():
        if key == "base":
            continue
        ok = val.lower() in palette
        if not ok:
            ng += 1
        print(("  ok   " if ok else "  FAIL ") + f"{name}.{key} {val}" + ("" if ok else " はパレットにない"))
print("all passed" if ng == 0 else f"{ng} failed")
sys.exit(1 if ng else 0)
