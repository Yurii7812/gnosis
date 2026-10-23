#!/usr/bin/env python3
"""題の移行（title_migrate.py）の試験。一時フォルダ（既定 ~/Desktop/test）の vault だけを使う。"""
import os
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import title_migrate as tm  # noqa: E402


class T(unittest.TestCase):
    def test_same(self):
        t = "---\ntime: 2026-01-01 00:00:00\ntitle: 題\n---\n\n# 題\n\n本文\n"
        self.assertEqual(tm.migrate_text(t), ("---\ntime: 2026-01-01 00:00:00\n---\n\n# 題\n\n本文\n", "same", "題"))

    def test_diverge_h1_wins(self):
        t = "---\ntime: x\ntitle: 古い題\n---\n\n# 新しい題\n"
        new, kind, title = tm.migrate_text(t)
        self.assertEqual((kind, title), ("diverge", "新しい題"))
        self.assertNotIn("title:", new)
        self.assertIn("# 新しい題", new)

    def test_no_h1_gets_one(self):
        t = "---\ntime: x\ntitle: 見出しなし\n---\n\n本文\n"
        new, kind, _ = tm.migrate_text(t)
        self.assertEqual(kind, "no_h1")
        self.assertEqual(new, "---\ntime: x\n---\n\n# 見出しなし\n\n本文\n")

    def test_only_title_in_fm_drops_front_matter(self):
        t = "---\ntitle: だけ\n---\n\n# だけ\n\n本文\n"
        new, kind, _ = tm.migrate_text(t)
        self.assertEqual(new, "# だけ\n\n本文\n")

    def test_no_title_untouched(self):
        t = "---\ntime: x\n---\n\n# A\n"
        self.assertEqual(tm.migrate_text(t), (t, "none", ""))
        self.assertEqual(tm.migrate_text("# プレーン\n本文\n")[1], "none")

    def test_h1_in_code_fence_is_not_a_heading(self):
        t = "---\ntitle: T\n---\n\n```\n# コード\n```\n"
        self.assertEqual(tm.migrate_text(t)[1], "no_h1")

    def test_other_lines_byte_identical_and_idempotent(self):
        t = "---\ntime: x\ntitle: T\nyomi:\n  \"T\": \"てぃー\"\nattribute: group\n---\n\n# T\n\nParentBranch:\n[p](p.md)\n"
        new, _, _ = tm.migrate_text(t)
        self.assertEqual(new, t.replace("title: T\n", ""))
        self.assertEqual(tm.migrate_text(new)[1], "none")

    def test_run_counts_and_dry_run(self):
        base = os.environ.get("TMPDIR") or str(Path.home() / "Desktop" / "test")
        os.makedirs(base, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=base) as d:
            r = Path(d)
            (r / "a.md").write_text("---\ntitle: A\n---\n\n# A\n")
            (r / "b.md").write_text("---\ntitle: B1\n---\n\n# B2\n")
            (r / "c.md").write_text("---\ntitle: C\n---\n\n本文\n")
            (r / "d.md").write_text("# D\n")
            res = tm.run(r, dry_run=True)
            self.assertEqual(res["counts"], {"same": 1, "diverge": 1, "no_h1": 1, "none": 1})
            self.assertEqual(res["diverged"], [{"path": "b.md", "title": "B1", "h1": "B2"}])
            self.assertIn("title: A", (r / "a.md").read_text())
            res = tm.run(r)
            self.assertNotIn("title:", (r / "a.md").read_text() + (r / "b.md").read_text() + (r / "c.md").read_text())
            self.assertEqual(tm.run(r)["counts"], {"same": 0, "diverge": 0, "no_h1": 0, "none": 4})


if __name__ == "__main__":
    unittest.main()
