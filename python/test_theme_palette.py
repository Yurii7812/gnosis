#!/usr/bin/env python3
"""組み込みテーマ（assets/themes/builtin.json）の確認。
- 起動画面（start）と旧アプリ用（app）は、配色エディタのカラーパレット（8 色相 × 9 段階）の色だけで作られている。
- 見た目の 3 つ（standard・light・dark）は読みやすさに合わせて細かく調整した色（エディタでは HEX で入力できる）。
  代わりに、背景とのコントラスト比が十分か（本文 7 以上、リンク・見出し・補助の文字 4.5 以上）を確かめる。"""
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
def lum(h):
    c = [int(h[i:i + 2], 16) / 255 for i in (1, 3, 5)]
    c = [x / 12.92 if x <= 0.03928 else ((x + 0.055) / 1.055) ** 2.4 for x in c]
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]


def contrast(a, b):
    x, y = sorted([lum(a), lum(b)], reverse=True)
    return (x + 0.05) / (y + 0.05)


ng = 0
for name in ("standard", "light", "dark"):
    t = themes[name]
    for key, need in (("fg", 7), ("link", 4.5), ("heading", 4.5), ("subheading", 4.5), ("muted", 4.5)):
        if key not in t:
            continue
        r = contrast(t[key], t["bg"])
        ok = r >= need
        if not ok:
            ng += 1
        print(("  ok   " if ok else "  FAIL ") + f"{name}.{key} {t[key]} コントラスト {r:.1f}（{need} 以上）")

for name, t in themes.items():
    if name not in ("start", "app"):
        continue
    for key, val in t.items():
        if key == "base":
            continue
        ok = val.lower() in palette
        if not ok:
            ng += 1
        print(("  ok   " if ok else "  FAIL ") + f"{name}.{key} {val}" + ("" if ok else " はパレットにない"))
print("all passed" if ng == 0 else f"{ng} failed")
sys.exit(1 if ng else 0)
