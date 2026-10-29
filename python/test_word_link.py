#!/usr/bin/env python3
"""word_link.py の単体試験: 題と同じ単語を、大文字小文字を区別せずリンクにする。"""
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import word_link as wl  # noqa: E402

HERE = Path(__file__).resolve().parent


class WordLinkTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(dir=str(Path.home() / "gnosis-work" / "test"))
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        for name, title in [("apple.md", "apple"), ("pie.md", "Apple Pie"), ("kaki.md", "語源"), ("x.md", "a")]:
            (self.root / name).write_text(f"---\ntime: 2026-01-01 00:00:00\n---\n\n# {title}\n\n本文\n", encoding="utf-8")
        (self.root / "sub").mkdir()
        (self.root / "sub" / "deep.md").write_text("---\ntime: 2026-01-01 00:00:00\n---\n\n# Deep Word\n", encoding="utf-8")
        self.body = [
            "---", "time: 2026-01-01 00:00:00", "---", "", "# 覚える", "",
            "Apple と apple と pineapple。語源を調べる。",
            "Apple Pie は別。`apple` はコード。[apple](apple.md) は既にリンク。",
            "```", "apple", "```",
            "a と deep word と DEEP WORD",
            "",
        ]
        self.note = self.root / "memo.md"
        self.note.write_text("\n".join(self.body), encoding="utf-8")

    def test_candidates_ignore_case_and_skip_protected_text(self):
        c = {w["title"]: w for w in wl.candidates(self.root, "memo.md", self.body, 0, 10 ** 9)}
        self.assertEqual(set(c), {"apple", "Apple Pie", "語源", "Deep Word"})  # 1 文字の題 a は対象外
        self.assertEqual(c["apple"]["count"], 2)       # 行 7 の Apple / apple のみ（pineapple・コード・既存リンク・コードブロックは除く）
        self.assertEqual(c["Apple Pie"]["count"], 1)   # 長い題が先: Apple Pie の Apple は apple に数えない
        self.assertEqual(c["Deep Word"]["count"], 2)

    def test_apply_links_only_chosen_words_keeping_original_case(self):
        out = wl.apply(self.root, "memo.md", self.body, 0, 10 ** 9, ["apple", "deep word"])
        self.assertIn("[Apple](apple.md) と [apple](apple.md) と pineapple。", out[6])
        self.assertIn("語源を調べる", out[6])                       # 選ばなかった語源はそのまま
        self.assertIn("Apple Pie は別", out[7])                    # 選ばなかった Apple Pie はそのまま（apple にもならない）
        self.assertIn("`apple` はコード", out[7])
        self.assertIn("[deep word](sub/deep.md) と [DEEP WORD](sub/deep.md)", out[11])
        self.assertEqual(out[4], "# 覚える")                      # 見出しは触らない

    def test_line_range_and_relative_path_from_subfolder(self):
        out = wl.apply(self.root, "memo.md", self.body, 11, 12, ["apple", "deep word"])
        self.assertEqual(out[6], self.body[6])                     # 範囲の外は変えない
        self.assertIn("[deep word](sub/deep.md)", out[11])
        sub = self.root / "sub" / "n.md"
        lines = ["# n", "", "apple"]
        sub.write_text("\n".join(lines), encoding="utf-8")
        self.assertEqual(wl.apply(self.root, "sub/n.md", lines, 0, 99, ["apple"])[2], "[apple](../apple.md)")

    def test_cli_roundtrip(self):
        r = subprocess.run([sys.executable, str(HERE / "word_link.py"), "candidates", str(self.root), str(self.note)],
                           stdout=subprocess.PIPE, text=True, check=True)
        self.assertIn("apple", [w["title"] for w in json.loads(r.stdout)["words"]])
        r = subprocess.run([sys.executable, str(HERE / "word_link.py"), "apply", str(self.root), str(self.note), "--words", '["語源"]'],
                           stdout=subprocess.PIPE, text=True, check=True)
        self.assertIn("[語源](kaki.md)を調べる", r.stdout)
        self.assertEqual(self.note.read_text(encoding="utf-8"), "\n".join(self.body))  # ファイルは書き換えない


if __name__ == "__main__":
    unittest.main()
