#!/usr/bin/env python3
"""Gnosis のアイコンとロゴを作る（Chnoubis の Unicode Braille アートから）。

    python3 tools/build_icons.py

作るもの（assets/ の下）:
  icons/gnosis-symbol.svg        シンボルだけ（ベクター。点を円で描く）
  icons/gnosis-<N>.png           シンボルだけのアイコン（16〜1024 px。夜空色の角丸地に水色）
  icons/gnosis.ico               Windows 用（16〜256）
  icons/gnosis.icns              macOS 用
  logo/gnosis-logo.svg           シンボル＋「Gnosis」の文字
  logo/gnosis-logo.png           同（横 1200 px）

正式な画像に差し替えるとき:
  assets/icons/source/symbol.png（正方形・透過可・1024 px 以上推奨）を置くと、Braille のアート
  の代わりにそれからアイコンを作る。ロゴも assets/logo/source/logo.png を置けばそれを使う。
  置いたら、このスクリプトをもう一度実行する。
必要なもの: Python 3 と Pillow（pip install pillow）。
"""
from __future__ import annotations

import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ART = ROOT / "assets" / "chnoubis" / "chnoubis-80.txt"
# インストール時は GNOSIS_ICON_OUTPUT_ROOT に生成して Git 管理の asset を書き換えない。
OUTPUT_ROOT = Path(os.environ.get("GNOSIS_ICON_OUTPUT_ROOT", ROOT / "assets"))
ICONS = OUTPUT_ROOT / "icons"
LOGO = OUTPUT_ROOT / "logo"
# 起動画面 Chnoubis #10 と同じ配色（assets/themes/builtin.json の start）。
# Desktop launcher symbol needs higher contrast than the main editor canvas.
BG = "#071827"
ACCENT = "#D7F8FF"
FG = "#E6EEF5"
SIZES = [16, 24, 32, 48, 64, 128, 256, 512, 1024]

# Braille の点の位置（ビット → 列, 行）。1 文字は 2 列 × 4 行の点
DOTS = [(0, 0), (0, 1), (0, 2), (1, 0), (1, 1), (1, 2), (0, 3), (1, 3)]


def dots_from_art(path: Path) -> tuple[list[tuple[int, int]], int, int]:
    lines = path.read_text(encoding="utf-8").rstrip("\n").split("\n")
    pts = []
    for y, line in enumerate(lines):
        for x, ch in enumerate(line):
            code = ord(ch) - 0x2800
            if not 0 <= code <= 0xFF:
                continue
            for bit, (dx, dy) in enumerate(DOTS):
                if code & (1 << bit):
                    pts.append((x * 2 + dx, y * 4 + dy))
    width = max(len(l) for l in lines) * 2
    height = len(lines) * 4
    return pts, width, height


def bbox(pts):
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    return min(xs), min(ys), max(xs) + 1, max(ys) + 1


def symbol_svg(pts) -> str:
    x0, y0, x1, y1 = bbox(pts)
    w, h = x1 - x0, y1 - y0
    side = max(w, h)
    pad = side * 0.035
    vb = side + 2 * pad
    ox = pad + (side - w) / 2 - x0
    oy = pad + (side - h) / 2 - y0
    circles = "".join(f'<circle cx="{x + ox + 0.5:.2f}" cy="{y + oy + 0.5:.2f}" r="0.55"/>' for x, y in pts)
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {vb:.2f} {vb:.2f}">\n'
            f'<title>Gnosis</title>\n'
            f'<rect width="{vb:.2f}" height="{vb:.2f}" rx="{vb * 0.18:.2f}" fill="{BG}"/>\n'
            f'<g fill="{ACCENT}">{circles}</g>\n</svg>\n')


def logo_svg(pts) -> str:
    x0, y0, x1, y1 = bbox(pts)
    w, h = x1 - x0, y1 - y0
    text_h = h * 0.42
    gap = h * 0.12
    total_w = w + gap + text_h * 3.2
    circles = "".join(f'<circle cx="{x - x0 + 0.5:.2f}" cy="{y - y0 + 0.5:.2f}" r="0.55"/>' for x, y in pts)
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {total_w:.2f} {h:.2f}">\n'
            f'<title>Gnosis</title>\n'
            f'<g fill="{ACCENT}">{circles}</g>\n'
            f'<text x="{w + gap:.2f}" y="{h / 2 + text_h * 0.36:.2f}" font-family="DejaVu Sans, Helvetica, Arial, sans-serif" '
            f'font-size="{text_h:.2f}" letter-spacing="{text_h * 0.06:.2f}" fill="{ACCENT}">Gnosis</text>\n</svg>\n')


def render_symbol(pts, size: int, Image, ImageDraw):
    """白い角丸の地に、点を黒い円で描く（大きく描いて縮める＝なめらか）"""
    scale = 4
    big = size * scale
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([0, 0, big - 1, big - 1], radius=big * 0.18, fill=BG)
    x0, y0, x1, y1 = bbox(pts)
    w, h = x1 - x0, y1 - y0
    side = max(w, h)
    pad = side * 0.035
    unit = big / (side + 2 * pad)
    ox = pad + (side - w) / 2 - x0
    oy = pad + (side - h) / 2 - y0
    r = max(0.55 * unit, 0.6)
    for x, y in pts:
        cx = (x + ox + 0.5) * unit
        cy = (y + oy + 0.5) * unit
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=ACCENT)
    return img.resize((size, size), Image.LANCZOS)


def main() -> int:
    ICONS.mkdir(parents=True, exist_ok=True)
    LOGO.mkdir(parents=True, exist_ok=True)
    pts, _w, _h = dots_from_art(ART)
    # Linux の SVG は Pillow が無い環境でも必ず最新版の色で生成する。
    (ICONS / "gnosis-symbol.svg").write_text(symbol_svg(pts), encoding="utf-8")
    (LOGO / "gnosis-logo.svg").write_text(logo_svg(pts), encoding="utf-8")
    try:
        from PIL import Image, ImageDraw, ImageFont
    except ImportError:
        print("Pillow 未導入: SVG アイコンを生成しました。PNG/ICNS は省略します。", file=sys.stderr)
        return 0

    src_symbol = ROOT / "assets" / "icons" / "source" / "symbol.png"
    if src_symbol.exists():
        base = Image.open(src_symbol).convert("RGBA")
        images = {s: base.resize((s, s), Image.LANCZOS) for s in SIZES}
    else:
        (ICONS / "gnosis-symbol.svg").write_text(symbol_svg(pts), encoding="utf-8")
        images = {s: render_symbol(pts, s, Image, ImageDraw) for s in SIZES}
    for s, im in images.items():
        im.save(ICONS / f"gnosis-{s}.png")
    images[256].save(ICONS / "gnosis.ico", sizes=[(s, s) for s in [16, 24, 32, 48, 64, 128, 256]])
    try:
        images[1024].save(ICONS / "gnosis.icns")
    except Exception as e:  # 古い Pillow
        print("icns を作れませんでした: " + str(e), file=sys.stderr)

    src_logo = ROOT / "assets" / "logo" / "source" / "logo.png"
    if src_logo.exists():
        Image.open(src_logo).convert("RGBA").save(LOGO / "gnosis-logo.png")
    else:
        (LOGO / "gnosis-logo.svg").write_text(logo_svg(pts), encoding="utf-8")
        sym = render_symbol(pts, 400, Image, ImageDraw)
        W, H = 1200, 400
        img = Image.new("RGBA", (W, H), BG)
        img.alpha_composite(sym, (0, 0))
        d = ImageDraw.Draw(img)
        font = None
        for name in ["DejaVuSans.ttf", "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", "Arial.ttf", "Helvetica.ttc"]:
            try:
                font = ImageFont.truetype(name, 170)
                break
            except Exception:
                continue
        if font is None:
            font = ImageFont.load_default()
        d.text((440, H / 2), "Gnosis", fill=ACCENT, font=font, anchor="lm")
        img.save(LOGO / "gnosis-logo.png")
    print("icons:", ", ".join(sorted(p.name for p in ICONS.glob("gnosis*"))))
    print("logo:", ", ".join(sorted(p.name for p in LOGO.glob("gnosis*"))))
    return 0


if __name__ == "__main__":
    sys.exit(main())
