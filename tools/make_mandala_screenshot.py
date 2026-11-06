#!/usr/bin/env python3
"""曼荼羅ビューのスクショ（docs/images/mandala-view.png）を作る。

一時フォルダの小さな vault（つながったノート）を開き、本物の Vim（Gnosis 専用 vimrc）で
曼荼羅ビューを左に出した画面を pyte で読んで、色つきで画像にする。make_start_screenshot.py の描画を使う。
本物の vault には触れない。使い方: python3 tools/make_mandala_screenshot.py
"""
from __future__ import annotations

import json
import os
import shutil
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "test"))
sys.path.insert(0, str(REPO / "tools"))
from keys_pty import Session  # noqa: E402
from make_start_screenshot import COLS, ROWS, render  # noqa: E402

# 中心のノートと、そこからつながるノート（ファイル名, 題, 本文のリンク先）
NOTES = {
    "260101000000.md": ("Gnosis", ["260101000001", "260101000002", "260101000003", "260101000004", "260101000005"]),
    "260101000001.md": ("ノートを書く", ["260101000006"]),
    "260101000002.md": ("リンクでつなぐ", []),
    "260101000003.md": ("曼荼羅ビュー", []),
    "260101000004.md": ("同期の規則", []),
    "260101000005.md": ("全文検索", []),
    "260101000006.md": ("Vim の基本", []),
}


def write_vault(v: Path) -> None:
    (v / "index.md").write_text("---\ntime: 2026-01-01 00:00:00\ntitle: Index\nattribute: group\n---\n\n# Index\n\n" + "".join(f"[{t}]({f})\n" for f, (t, _) in NOTES.items()), encoding="utf-8")
    for fn, (title, links) in NOTES.items():
        body = [f"---\ntime: 2026-01-01 00:00:00\n---\n", f"# {title}\n", "本文。\n"]
        for lk in links:
            body.append(f"[{NOTES[lk + '.md'][0]}]({lk}.md)\n")
        body.append("\n### Context\n")
        (v / fn).write_text("\n".join(body), encoding="utf-8")


def main() -> None:
    out = REPO / "docs" / "images" / "mandala-view.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    base = os.environ.get("TMPDIR") or str(Path.home() / "gnosis-work" / "test")
    os.makedirs(base, exist_ok=True)
    work = Path(tempfile.mkdtemp(dir=base, prefix="mandala-"))
    try:
        v = work / "ノート"
        v.mkdir()
        write_vault(v)
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
            s.send("\r", 3.0)  # 起動メニューで vault を開く（曼荼羅ビューが左に出る）
            render(s.screen, out)
        print(out)
    finally:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    main()
