#!/usr/bin/env python3
import contextlib
import hashlib
import io
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import note_tools as nt


class NoteToolsTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(dir=str(Path.home() / "Desktop" / "test"))
        self.addCleanup(self.tmp.cleanup)
        r = self.root = Path(self.tmp.name)
        (r / "a.md").write_text("---\ntime: 2026-01-01 00:00:00\ntitle: 甲\n---\n\n# 甲\n\n日本語の本文です。Hello world foo-bar.\n[リンク先](b.md)を見る\n- [ ] 未完了\n- [x] 完了\n\n## 小見出し\n\n終わり\n\nParentBranch:\n[親の長い名前](p.md)\n", encoding="utf-8")
        (r / "b.md").write_text("---\ntime: 2026-01-01 00:00:00\ntitle: 乙\n---\n\n# 乙\n\n日本語の本文です。Hello world foo-bar.\n[リンク先](c.md)を見る\n- [ ] 未完了\n追加の行\n", encoding="utf-8")
        (r / "empty.md").write_text("---\ntitle: 空\n---\n\n# 空\n", encoding="utf-8")
        (r / "same.md").write_text((r / "b.md").read_text(encoding="utf-8"), encoding="utf-8")
        self.before = {p.name: hashlib.md5(p.read_bytes()).hexdigest() for p in r.glob("*.md")}

    def same(self):
        self.assertEqual(self.before, {p.name: hashlib.md5(p.read_bytes()).hexdigest() for p in self.root.glob("*.md") if p.name in self.before})   # 最初からあったノートが不変

    def test_stats_counts_exclude_front_matter_and_relations(self):
        n = nt.stats(self.root, "a.md")["note"]
        self.assertEqual((n["tasks_open"], n["tasks_done"], n["links"], n["headings"]), (1, 1, 1, 2))
        self.assertEqual(n["words"], 3)                                          # Hello world foo-bar（ハイフンは 1 語）
        # 関係ブロックの「親の長い名前」(7 文字)が数えられていないこと: 同じ本文から ParentBranch を除いたノートと文字数が一致
        (self.root / "a2.md").write_text("---\ntitle: 甲\n---\n\n# 甲\n\n日本語の本文です。Hello world foo-bar.\n[リンク先](b.md)を見る\n- [ ] 未完了\n- [x] 完了\n\n## 小見出し\n\n終わり\n", encoding="utf-8")
        self.assertEqual(nt.stats(self.root, "a2.md")["note"]["chars"], n["chars"])
        # リンクは表示の文字だけ数える（URL の b.md は数えない）
        (self.root / "l.md").write_text("# L\n\n[あいう](very-long-target-name.md)\n", encoding="utf-8")
        self.assertEqual(nt.stats(self.root, "l.md")["note"]["chars"], len("Lあいう"))
        self.same()

    def test_stats_vault_and_empty(self):
        s = nt.stats(self.root)
        self.assertEqual(s["notes"], 4)
        self.assertEqual(s["empty"], ["empty.md"])                               # 題だけのノートだけが「空」
        self.assertIn("empty.md", s["empty"])
        self.assertEqual(s["largest"][0]["path"], "a.md")
        self.assertEqual(s["total"]["tasks_open"], 3)
        with self.assertRaises(ValueError):
            nt.stats(self.root, "nope.md")

    def test_diff_similarity_and_lines(self):
        d = nt.diff(self.root, "a.md", "b.md")
        self.assertFalse(d["identical"])
        self.assertGreater(d["common_lines"], 2)
        self.assertGreater(d["only_a"], 0)
        self.assertTrue(any(x.startswith("-[リンク先](b.md)を見る") for x in d["diff"]))
        self.assertTrue(any(x.startswith("+[リンク先](c.md)を見る") for x in d["diff"]))
        self.assertTrue(any(x.startswith("+追加の行") for x in d["diff"]))
        same = nt.diff(self.root, "b.md", "same.md")
        self.assertTrue(same["identical"])
        self.assertEqual((same["similarity"], same["diff"]), (1.0, []))
        self.assertLess(nt.diff(self.root, "a.md", "empty.md")["similarity"], 0.3)
        self.same()

    def test_markdown_and_cli(self):
        def run(*a):
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                rc = nt.main([str(self.root), *a])
            return rc, buf.getvalue()
        self.assertIn("# 統計: [甲](a.md)", run("stats", "a.md", "--md")[1])
        self.assertIn("# vault の統計", run("stats", "--md")[1])
        self.assertIn("```diff", run("diff", "a.md", "b.md", "--md")[1])
        self.assertIn("同じ内容です", run("diff", "b.md", "same.md", "--md")[1])
        self.assertEqual(run("diff", "a.md")[0], 1)
        self.assertEqual(run("bogus")[0], 2)
        self.same()


if __name__ == "__main__":
    unittest.main()
