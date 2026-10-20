#!/usr/bin/env python3
import contextlib, hashlib, io, sys, tempfile, unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import dedupe as dd
import versions as vs

P1 = "水やりは朝に行うのがよい。夕方に行うと葉が濡れたまま夜を迎えて病気の原因になる。"
P2 = "Tomatoes need at least six hours of direct sunlight every single day to fruit well."


def note(title, body):
    return f"---\ntime: 2026-01-01 00:00:00\ntitle: {title}\n---\n\n# {title}\n\n{body}"


class T(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory(dir=str(Path.home() / "Desktop" / "test"))
        self.addCleanup(tmp.cleanup)
        self.r = Path(tmp.name)

    def w(self, name, text):
        (self.r / name).write_text(text, encoding="utf-8")

    def test_scan_identical_and_shared(self):
        self.w("a.md", note("甲", P1 + "\n\n" + P2 + "\n"))
        self.w("b.md", note("乙", P1.replace("。", "。 ") + "\n\n" + P2.upper() + "\n"))       # 空白・大文字小文字・全角半角の違いは無視
        self.w("c.md", note("丙", P1 + "\n\nまったく別の、三十文字を超える長さの段落をここに置いておきます。\n"))
        self.w("d.md", note("丁", "短い\n\n# 見出し\n\n[リンク](a.md)\n"))
        r = dd.scan(self.r)
        self.assertEqual(r["identical"], [["a.md", "b.md"]])                     # 本文が同じ組(題は違っても)
        self.assertEqual(r["shared_total"], 1)                                   # P1 が c にもある(a,b だけの P2 は組として報告済み)
        self.assertEqual(sorted(e["path"] for e in r["shared"][0]["notes"]), ["a.md", "b.md", "c.md"])
        self.assertIn("本文が同じノート", dd.to_md("scan", r))

    def test_scan_ignores_code_front_matter_relations_and_short(self):
        self.w("a.md", note("甲", "```\n" + P1 + "\n```\n\nRelated:\n[x](x.md)\n\n短い段落\n"))
        self.w("b.md", note("乙", "```\n" + P1 + "\n```\n\nRelated:\n[x](x.md)\n\n短い段落\n\n乙だけの別の段落\n"))
        r = dd.scan(self.r)
        self.assertEqual((r["identical"], r["shared_total"]), ([], 0))
        self.assertEqual(dd.scan(self.r, 1)["shared_total"], 1)                  # --min で短い段落も対象にできる

    def test_inner_dry_run_and_apply_with_version(self):
        body = P1 + "\n\n" + P2 + "\n\n" + P1 + "\n\n途中の別の段落もある程度の長さにして置いておきます、はい。\n\n" + P2.lower() + "\n"
        self.w("a.md", note("甲", body))
        before = (self.r / "a.md").read_bytes()
        d = dd.inner(self.r, "a.md")
        self.assertEqual([x["first_line"] for x in d["duplicates"]], [8, 10])
        self.assertFalse(d["applied"])
        self.assertEqual((self.r / "a.md").read_bytes(), before)                 # 見せるだけ
        a = dd.inner(self.r, "a.md", apply=True)
        self.assertTrue(a["applied"])
        t = (self.r / "a.md").read_text(encoding="utf-8")
        self.assertEqual(t.count(P1), 1)
        self.assertEqual(t.lower().count(P2.lower()), 1)
        self.assertIn("途中の別の段落", t)
        self.assertNotIn("\n\n\n", t)                                            # 空行が溜まらない
        self.assertIn("# 甲", t)
        self.assertEqual(len(vs.list_versions(self.r, "a.md")["versions"]), 1)  # 除く前の内容が版に残った
        vs.restore(self.r, "a.md", 1)
        self.assertEqual((self.r / "a.md").read_bytes(), before)
        self.assertEqual(dd.inner(self.r, "a.md", apply=True)["applied"], True)
        self.assertEqual(dd.inner(self.r, "a.md", apply=True)["duplicates"], [])  # 2 回目は何もない
        self.assertFalse(dd.inner(self.r, "a.md", apply=True)["applied"])

    def test_inner_errors_and_cli(self):
        self.w("a.md", note("甲", P1 + "\n"))
        for bad in ("../x.md", "nope.md", ".h/x.md"):
            with self.assertRaises(ValueError):
                dd.inner(self.r, bad)
        self.assertEqual(dd.inner(self.r, "a.md")["duplicates"], [])
        def run(*a):
            b = io.StringIO()
            with contextlib.redirect_stdout(b):
                rc = dd.main([str(self.r), *a])
            return rc, b.getvalue()
        self.assertIn("繰り返しはありません", run("inner", "a.md", "--md")[1])
        self.assertIn("# 本文の重複", run("scan", "--md")[1])
        self.assertEqual(run("inner", "zz.md")[0], 1)
        self.assertEqual(run("bogus")[0], 2)


if __name__ == "__main__":
    unittest.main()
