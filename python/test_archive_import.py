#!/usr/bin/env python3
"""archive_import.py の試験（一時フォルダだけを使う。7z が無い環境では飛ばす）。"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import archive_import as ai  # noqa: E402

SEVENZ = ai.find_7z()


@unittest.skipUnless(SEVENZ, "7z が無い")
class T(unittest.TestCase):
    def setUp(self):
        base = os.environ.get("TMPDIR") or str(Path.home() / "gnosis-work" / "test")
        os.makedirs(base, exist_ok=True)
        self.tmp = tempfile.TemporaryDirectory(dir=base)
        t = Path(self.tmp.name)
        self.root = t / "vault"
        self.root.mkdir()
        (self.root / "a.md").write_text("old\n")
        (self.root / "same.md").write_text("hi\n")
        src = t / "src" / "v"
        (src / ".state").mkdir(parents=True)
        (src / "sub").mkdir()
        (src / "a.md").write_text("NEW\n")
        (src / "same.md").write_text("hi\n")
        (src / "sub" / "c.md").write_text("c\n")
        (src / ".state" / "s").write_text("x")
        os.symlink("/etc/passwd", src / "link.md")
        self.plain = t / "plain.zip"
        self.locked = t / "locked.7z"
        subprocess.run([SEVENZ, "a", "-tzip", "-snl", str(self.plain), "v"], cwd=t / "src", check=True, capture_output=True)
        subprocess.run([SEVENZ, "a", "-t7z", "-snl", "-mhe=on", "-ppw", str(self.locked), "v"], cwd=t / "src", check=True, capture_output=True)

    def tearDown(self):
        self.tmp.cleanup()

    def test_plan_and_apply(self):
        p = ai.plan(str(self.root), str(self.plain), None)
        self.assertEqual(p["new"], ["sub/c.md"], p)
        self.assertEqual(p["changed"], ["a.md"], p)
        self.assertEqual(p["same"], ["same.md"], p)
        self.assertEqual((self.root / "a.md").read_text(), "old\n")  # plan では触らない
        r = ai.apply(str(self.root), p["stage"])
        self.assertEqual((r["added"], r["updated"]), (1, 1), r)
        self.assertEqual((self.root / "a.md").read_text(), "NEW\n")
        self.assertEqual((self.root / "sub" / "c.md").read_text(), "c\n")
        self.assertEqual((Path(r["backup"]) / "a.md").read_text(), "old\n")  # 元は残る
        self.assertFalse((self.root / ".state").exists())
        self.assertFalse((self.root / "link.md").exists())
        self.assertFalse(Path(p["stage"]).exists())

    def test_password(self):
        self.assertTrue(ai.plan(str(self.root), str(self.locked), None).get("need_password"))
        bad = ai.plan(str(self.root), str(self.locked), "bad")
        self.assertTrue(bad.get("need_password") and bad.get("wrong"), bad)
        ok = ai.plan(str(self.root), str(self.locked), "pw")
        self.assertEqual(ok["changed"], ["a.md"], ok)
        ai.discard(ok["stage"])
        self.assertFalse(Path(ok["stage"]).exists())

    def test_missing_archive(self):
        self.assertIn("error", ai.plan(str(self.root), str(self.root / "nope.7z"), None))


if __name__ == "__main__":
    unittest.main()
