#!/usr/bin/env python3
import contextlib
import hashlib
import io
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import diagnose as dg


def wr(root, name, text, binary=False):
    (root / name).write_bytes(text if binary else text.encode("utf-8"))


class DiagnoseTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(dir=str(Path.home() / "Desktop" / "test"))
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)

    def snapshot(self):
        return {str(p.relative_to(self.root)): hashlib.md5(p.read_bytes()).hexdigest() for p in self.root.rglob("*") if p.is_file()}

    def codes(self, name, level="info"):
        r = dg.compat(self.root, level)
        return {(x["code"], x["line"]) for x in r["items"] if x["file"] == name}

    def test_clean_note_has_no_problem(self):
        wr(self.root, "ok.md", "---\ntitle: 良\n---\n\n# 良\n\n## 節\n\n本文 [リンク](ok.md) と表\n\n| a | b |\n|---|---|\n| 1 | 2 |\n")
        self.assertEqual(self.codes("ok.md"), set())

    def test_broken_syntax_is_error(self):
        wr(self.root, "bad.md", "---\ntitle: x\n\n# 閉じない\n")
        wr(self.root, "fence.md", "# 題\n\n```python\nprint(1)\n\n本文のつもり\n")
        wr(self.root, "table.md", "# 表\n\n| a | b |\n|---|---|\n| 1 | 2 | 3 |\n| 4 |\n")
        self.assertIn(("frontmatter-unclosed", 1), self.codes("bad.md", "error"))
        self.assertIn(("fence-unclosed", 3), self.codes("fence.md", "error"))
        t = self.codes("table.md", "error")
        self.assertEqual({x for x in t if x[0] == "table-columns"}, {("table-columns", 5), ("table-columns", 6)})   # 区切り行は数えない

    def test_closed_fence_with_inner_hash_and_tilde_fence(self):
        wr(self.root, "f.md", "# 題\n\n```\n## 見出しではない\n| 表でもない |\n| a | b |\n```\n\n~~~\n```\n~~~\n")
        self.assertEqual(self.codes("f.md"), set())                          # コードの中は検査しない・~~~ の中の ``` で閉じない

    def test_warnings(self):
        wr(self.root, "w.md", b"\xef\xbb\xbf" + "# BOM\r\n\r\nlf only\n[空白](a b.md)\n[ok](a%20b.md)\n![図](nothing.png)\n![有](w.md)\n".encode("utf-8"), binary=True)
        c = self.codes("w.md", "warn")
        self.assertIn(("bom", 1), c)
        self.assertIn(("mixed-eol", 1), c)
        self.assertIn(("link-space", 4), c)
        self.assertIn(("image-missing", 6), c)
        self.assertNotIn(("link-space", 5), c)                               # %20 は正しい
        self.assertFalse(any(x[1] == 7 for x in c))                         # 存在する画像(ここでは w.md 自身)は指摘しない

    def test_duplicate_and_skipped_headings(self):
        wr(self.root, "h.md", "# 題\n\n### 飛んだ\n\n## 同じ\n\n## 同じ\n")
        c = self.codes("h.md")
        self.assertIn(("heading-skip", 3), c)
        self.assertIn(("heading-duplicate", 7), c)

    def test_extensions_are_info_not_errors(self):
        wr(self.root, "e.md", "# 題\n\n==強調== と ⏰ 2026-10-25\n- 🌱 運動 2026-10-21\n\nGroup:\n[G](g.md)\n")
        r = dg.compat(self.root, "info")
        ext = [x for x in r["items"] if x["code"] == "extension"]
        self.assertEqual({x["level"] for x in ext}, {"info"})
        names = " ".join(x["message"] for x in ext)
        for k in ("==", "⏰", "🌱", "関係ブロック"):
            self.assertIn(k, names)
        self.assertEqual(dg.compat(self.root, "warn")["counts"]["info"], 0)      # warn 以上に絞ると info は出ない
        self.assertEqual(dg.compat(self.root, "error")["items"], [])

    def test_encoding_error(self):
        wr(self.root, "enc.md", b"# \xff\xfe broken\n", binary=True)
        self.assertIn(("encoding", 1), self.codes("enc.md", "error"))

    def test_read_only_and_ordering(self):
        wr(self.root, "a.md", "```\nopen\n")
        wr(self.root, "b.md", "# b\n\n==x==\n")
        before = self.snapshot()
        r = dg.compat(self.root)
        self.assertEqual(before, self.snapshot())
        self.assertEqual([x["level"] for x in r["items"]], sorted((x["level"] for x in r["items"]), key=lambda l: dg.RANK[l]))   # error → warn → info の順
        with self.assertRaises(ValueError):
            dg.compat(self.root, "debug")

    def test_profile_is_read_only_and_leaves_no_index_in_vault(self):
        for i in range(30):
            wr(self.root, f"n{i}.md", f"---\ntime: 2026-01-01 00:00:00\ntitle: n{i}\n---\n\n# n{i}\n\n本文 {i} " + "あ" * 200 + "\n")
        before = self.snapshot()
        r = dg.profile(self.root)
        self.assertEqual((r["notes"], r["nodes"]), (30, 30))
        self.assertEqual(set(r["seconds"]), {"read_all", "graph", "full_text_index", "similarity_corpus"})
        self.assertTrue(all(v is not None and v >= 0 for v in r["seconds"].values()))
        self.assertEqual(len(r["largest"]), 5)
        self.assertEqual(before, self.snapshot())                              # 索引(.gnosis)などを vault に作らない
        self.assertFalse((self.root / ".gnosis").exists())
        self.assertIn("実測値", r["note_text"])

    def test_cli(self):
        wr(self.root, "a.md", "# a\n\n```\nopen\n")
        def run(*a):
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                rc = dg.main([str(self.root), *a])
            return rc, buf.getvalue()
        self.assertIn("## error", run("compat", "--md")[1])
        self.assertIn("(a.md):3", run("compat", "--level", "error", "--md")[1])
        self.assertIn("# 性能診断", run("profile", "--md")[1])
        self.assertEqual(run("compat", "--level", "bogus")[0], 1)
        self.assertEqual(run("bogus")[0], 2)


if __name__ == "__main__":
    unittest.main()
