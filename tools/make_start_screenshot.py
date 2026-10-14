#!/usr/bin/env python3
"""起動画面のスクリーンショット（docs/images/start-screen.png）を作る。

本物の Vim（Gnosis 専用 vimrc）を擬似端末で動かし、起動画面を pyte で読んで、色つきで画像にする。
一時フォルダの vault と Gnosis ホームだけを使う（本物の vault には触れない）。
必要なもの: Python 3・Pillow・pyte・Vim。  使い方: python3 tools/make_start_screenshot.py
"""
from __future__ import annotations

import json
import os
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "test"))
from keys_pty import Session  # noqa: E402
from PIL import Image, ImageDraw, ImageFont  # noqa: E402

COLS, ROWS = 100, 40
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"
FONT_B = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf"
CJK = next((p for p in ("/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc", "/usr/share/fonts/truetype/noto/NotoSansCJK-Regular.ttc") if os.path.exists(p)), FONT)
SIZE = 18
DEFAULT_BG, DEFAULT_FG = "14283d", "e6eef5"


def color(c: str, default: str) -> tuple[int, int, int]:
    if c == "default" or not c:
        c = default
    if len(c) == 6:
        try:
            return tuple(int(c[i:i + 2], 16) for i in (0, 2, 4))  # type: ignore[return-value]
        except ValueError:
            pass
    return tuple(int(DEFAULT_FG[i:i + 2], 16) for i in (0, 2, 4)) if default == DEFAULT_FG else tuple(int(DEFAULT_BG[i:i + 2], 16) for i in (0, 2, 4))  # type: ignore[return-value]


def render(screen, out: Path) -> None:
    f, fb, fc = ImageFont.truetype(FONT, SIZE), ImageFont.truetype(FONT_B, SIZE), ImageFont.truetype(CJK, SIZE)
    cw = int(f.getlength("M"))
    ch = int(SIZE * 1.25)
    img = Image.new("RGB", (cw * COLS + 24, ch * ROWS + 24), tuple(int(DEFAULT_BG[i:i + 2], 16) for i in (0, 2, 4)))
    d = ImageDraw.Draw(img)
    for y in range(ROWS):
        x = 0
        while x < COLS:
            cell = screen.buffer[y][x]
            data = cell.data
            bg = color(cell.bg, DEFAULT_BG)
            fg = color(cell.fg, DEFAULT_FG)
            wide = data and ord(data[0]) > 0x2E7F and not (0x2800 <= ord(data[0]) <= 0x28FF)
            w = 2 if wide else 1
            if cell.reverse:
                fg, bg = bg, fg
            px, py = 12 + x * cw, 12 + y * ch
            d.rectangle([px, py, px + cw * w - 1, py + ch - 1], fill=bg)
            if data and 0x2800 <= ord(data[0]) <= 0x28FF:
                # Braille の点は、フォントに頼らず円で描く（2 列 × 4 行）
                code = ord(data[0]) - 0x2800
                pos = [(0, 0), (0, 1), (0, 2), (1, 0), (1, 1), (1, 2), (0, 3), (1, 3)]
                r = max(1.6, cw * 0.17)
                for bit, (dx, dy) in enumerate(pos):
                    if code & (1 << bit):
                        cx, cy = px + cw * (0.28 + 0.44 * dx), py + ch * (0.12 + 0.25 * dy + 0.06)
                        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=fg)
            elif data and data.strip():
                font = fc if wide else (fb if cell.bold else f)
                d.text((px, py), data, font=font, fill=fg)
                if cell.underscore:
                    d.line([px, py + ch - 3, px + cw * w - 1, py + ch - 3], fill=fg)
            x += w
    img.save(out, optimize=True)


def main() -> None:
    out = REPO / "docs" / "images" / "start-screen.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    base = os.environ.get("TMPDIR") or str(Path.home() / "Desktop" / "test")
    os.makedirs(base, exist_ok=True)
    work = Path(tempfile.mkdtemp(dir=base, prefix="shot-"))
    try:
        v = work / "ノート"
        v.mkdir()
        (v / "index.md").write_text("---\ntime: 2026-01-01 00:00:00\ntitle: Index\nattribute: group\n---\n\n# Index\n", encoding="utf-8")
        gh = work / "gh"
        gh.mkdir()
        (gh / "vaults.json").write_text(json.dumps({"version": 1, "last": str(v), "vaults": [{"path": str(v), "name": "ノート"}]}), encoding="utf-8")
        (v / ".gnosis").mkdir()
        (v / ".gnosis" / "settings.json").write_text(json.dumps({"version": 1, "language": "ja"}), encoding="utf-8")
        rc = work / "vimrc"
        rc.write_text(f"source {REPO}/vimrc_gnosis\n", encoding="utf-8")
        home = work / "home"
        home.mkdir()
        with Session(str(rc), str(home), str(gh), rows=ROWS, cols=COLS) as s:
            s.wait(1.5)
            render(s.screen, out)
        print(out)
    finally:
        import shutil
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    main()
