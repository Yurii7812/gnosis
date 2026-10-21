#!/usr/bin/env python3
"""曼荼羅ビューの元データ（mandala_view.py）の試験。一時フォルダ（既定 ~/Desktop/test）の vault だけを使う。"""
import os
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import mandala_view as mv  # noqa: E402


def note(title, attr=False, groups=(), body=()):
    s = f"---\ntime: 2026-01-01 00:00:00\ntitle: {title}\n" + ("attribute: group\n" if attr else "") + f"---\n\n# {title}\n\n"
    if groups:
        s += "Group:\n" + "".join(f"[{t}]({f})\n" for t, f in groups) + "\n"
    return s + "".join(b + "\n" for b in body)


class T(unittest.TestCase):
    def setUp(self):
        base = os.environ.get("TMPDIR") or str(Path.home() / "Desktop" / "test")
        os.makedirs(base, exist_ok=True)
        self.tmp = tempfile.TemporaryDirectory(dir=base)
        r = Path(self.tmp.name)
        (r / "index.md").write_text(note("Index", body=["[植物](plant.md)", "[料理](cook.md)", "[壊れた](nothing.md)"]))
        (r / "plant.md").write_text(note("植物", True, [("Index", "index.md")], ["[ハーブ](herb.md)", "[栽培](grow.md)", "[下位](sub.md)"]))
        (r / "cook.md").write_text(note("料理", True, [("Index", "index.md")], ["[ハーブ](herb.md)"]))
        (r / "sub.md").write_text(note("下位", True, [("植物", "plant.md")]))
        (r / "herb.md").write_text(note("ハーブ", False, [("植物", "plant.md"), ("料理", "cook.md")], ["[栽培](grow.md)", "[自分](herb.md)"]))
        (r / "grow.md").write_text(note("栽培", False, [("植物", "plant.md")]))
        self.d = mv.dump(r)

    def tearDown(self):
        self.tmp.cleanup()

    def test_note_center(self):
        self.assertEqual(mv.items(self.d, "herb.md", "groups"), ["plant.md", "cook.md"])
        self.assertEqual(mv.items(self.d, "herb.md", "notes"), ["grow.md"])  # 自分へのリンクは出さない
        self.assertEqual(mv.items(self.d, "herb.md", "all"), ["plant.md", "cook.md", "grow.md"])

    def test_group_center(self):
        self.assertEqual(mv.items(self.d, "plant.md", "all"), ["herb.md", "grow.md", "sub.md"])
        self.assertEqual(mv.items(self.d, "plant.md", "groups"), ["sub.md"])
        self.assertEqual(mv.items(self.d, "plant.md", "notes"), ["herb.md", "grow.md"])

    def test_index_center_skips_broken(self):
        self.assertEqual(mv.items(self.d, "index.md", "all"), ["plant.md", "cook.md"])
        self.assertTrue(self.d["nodes"]["index.md"]["g"])

    def test_unknown(self):
        self.assertEqual(mv.items(self.d, "x.md"), [])


if __name__ == "__main__":
    unittest.main()
