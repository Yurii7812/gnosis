#!/usr/bin/env python3
"""scan_inbox.py の step（矢印で番号を付ける）と undo（取り消し）の試験。一時フォルダだけを使う。"""
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import paper_pkm as pp  # noqa: E402
import scan_inbox as si  # noqa: E402

PNG = bytes.fromhex("89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c4890000000d49444154789c6360000002000001e221bc330000000049454e44ae426082")


class T(unittest.TestCase):
    def setUp(self):
        base = os.environ.get("TMPDIR") or str(Path.home() / "gnosis-work" / "test")
        os.makedirs(base, exist_ok=True)
        self.tmp = tempfile.TemporaryDirectory(dir=base)
        self.root = Path(self.tmp.name) / "vault"
        self.root.mkdir()
        (self.root / "index.md").write_text("---\ntime: 2026-01-01 00:00:00\nattribute: group\n---\n\n# Index\n", encoding="utf-8")
        d = Path(self.tmp.name) / "photos"
        d.mkdir()
        for i in range(5):
            (d / ("p%d.png" % i)).write_bytes(PNG + bytes([i]))
        si.import_files(self.root, [str(d)])
        self.names = si.list_scans(self.root)["scans"]

    def tearDown(self):
        self.tmp.cleanup()

    def test_step_down_and_right(self):
        r = si.assign(self.root, self.names[0], "1")
        self.assertTrue(r["ok"], r)
        r = si.step(self.root, self.names[1], "down")
        self.assertEqual(r["display"], "PA-1a", r)
        r = si.step(self.root, self.names[2], "right")
        self.assertEqual(r["display"], "PA-1b", r)
        r = si.step(self.root, self.names[3], "down")
        self.assertEqual(r["display"], "PA-1b1", r)
        self.assertEqual(si.list_scans(self.root)["last"], "PA-1b1")

    def test_step_needs_a_previous_number(self):
        r = si.step(self.root, self.names[0], "down")
        self.assertFalse(r["ok"])
        self.assertIn("Space", r["error"])

    def test_undo_restores_image_and_last(self):
        si.assign(self.root, self.names[0], "1")
        si.step(self.root, self.names[1], "down")           # 1a
        self.assertTrue((self.root / "PA-1a.png").is_file())
        r = si.undo(self.root)
        self.assertTrue(r["ok"], r)
        self.assertEqual((r["name"], r["last"]), (self.names[1], "PA-1"))
        self.assertFalse((self.root / "PA-1a.png").exists())
        self.assertIn(self.names[1], si.list_scans(self.root)["scans"])
        self.assertEqual(si.list_scans(self.root)["last"], "PA-1")
        # 作ったノートは vault から無くなる（.trash にある）
        self.assertNotIn("PA-1a", pp.scan_folgezettel_notes(self.root))
        self.assertTrue(list((self.root / ".trash").glob("*.md")))
        # もう一度取り消すと 1 も戻る。そのあとは取り消せない
        self.assertTrue(si.undo(self.root)["ok"])
        self.assertEqual(si.list_scans(self.root)["last"], "")
        self.assertFalse(si.undo(self.root)["ok"])

    def test_undo_refuses_when_a_number_was_overwritten(self):
        si.assign(self.root, self.names[0], "1")
        si.assign(self.root, self.names[1], "1")            # 同じ番号を上書き
        r = si.undo(self.root)
        self.assertFalse(r["ok"], r)
        self.assertIn("上書き", r["error"])
        self.assertTrue((self.root / "PA-1.png").is_file())


if __name__ == "__main__":
    unittest.main()
