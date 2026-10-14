#!/usr/bin/env python3
"""新規ノート（zn → Enter）の本文入力位置を、擬似端末で本物の Vim に打鍵して確かめる。

Context が H1 の直後に入った新規ノートを開いたら、すぐ挿入モードで本文が打てて、打った文字は
Context リンクの後ろの空行（3 行の真ん中）に入ること。一時フォルダ（~/Desktop/test）だけを使う。
"""
from __future__ import annotations

import os
import shutil
import sys
import tempfile
import time
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
try:
    import pyte  # noqa: F401
except ImportError:
    print("skip: pyte が無いため新規ノートの入力位置の擬似端末試験を省略")
    sys.exit(0)
from keys_pty import ESC, Session  # noqa: E402

REPO = Path(__file__).resolve().parent.parent
TMP_BASE = os.environ.get("TMPDIR") or str(Path.home() / "Desktop" / "test")


class TestNewNoteCursor(unittest.TestCase):
    def setUp(self) -> None:
        os.makedirs(TMP_BASE, exist_ok=True)
        self.work = Path(tempfile.mkdtemp(dir=TMP_BASE, prefix="ctxpty-"))
        self.addCleanup(shutil.rmtree, self.work, True)
        self.v = self.work / "vault"
        self.v.mkdir()
        (self.v / "index.md").write_text("---\ntitle: Index\nattribute: group\n---\n\n# Index\n", encoding="utf-8")
        (self.v / "a.md").write_text("---\ntime: 2026-01-01 00:00:00\ntitle: ノートA\n---\n\n# ノートA\n\n本文A。\n", encoding="utf-8")
        self.home = self.work / "home"
        self.home.mkdir()
        rc = self.work / "vimrc"
        rc.write_text(f"source {REPO}/vimrc_gnosis\nlet g:gnosis_root = '{self.v}/'\nlet g:gnosis_start_screen = 0\n"
                      "let g:gnosis_skip_interactive_mount = 1\nlet g:gnosis_autosync = 0\nlet g:gnosis_diary_auto = 0\n", encoding="utf-8")
        self.rc = str(rc)

    def test_zn_enter_types_into_the_middle_blank_line(self) -> None:
        with Session(self.rc, str(self.home), str(self.home), args=[str(self.v / "a.md")]) as s:
            s.send("zn", 0.6)
            s.send("\r", 1.5)       # 位置キー Enter（本文の最後・Context と Branch が付く）
            s.send("ここに書く", 0.6)  # 挿入モードのまま、すぐ書ける
            s.send(ESC, 0.9)
            s.send(":wa\r", 0.6)
            s.send(":qa!\r", 0.4)
        new = sorted(p for p in self.v.glob("2*.md"))
        self.assertEqual(len(new), 1, [p.name for p in self.v.iterdir()])
        lines = new[0].read_text(encoding="utf-8").split("\n")
        i = lines.index("Context:")
        self.assertEqual(lines[i + 1], "[ノートA](a.md)")
        self.assertEqual(lines[i + 2:i + 5], ["", "ここに書く", ""], lines)  # 空行・カーソル行・空行
        self.assertEqual(lines[i - 2], "# " + new[0].stem)
        self.assertEqual(lines[i - 1], "")
        self.assertEqual(lines[i + 5], "### ParentBranch")
        self.assertNotIn("### Context", lines)
        a = (self.v / "a.md").read_text(encoding="utf-8")
        self.assertIn("### ChildBranch", a)
        self.assertIn(f"[{new[0].stem}]({new[0].name})", a)
        self.assertNotIn("Context:", a)


if __name__ == "__main__":
    unittest.main(verbosity=1)
