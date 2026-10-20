#!/usr/bin/env python3
import contextlib, datetime as dt, hashlib, io, sys, tempfile, unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import versions as vs

T0 = dt.datetime(2026, 10, 21, 10, 0, 0)


class T(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory(dir=str(Path.home() / "Desktop" / "test"))
        self.addCleanup(tmp.cleanup)
        self.r = Path(tmp.name)
        self.n = self.r / "a.md"
        self.n.write_text("v1\n", encoding="utf-8")

    def test_save_list_dedupe(self):
        self.assertTrue(vs.save(self.r, "a.md", T0)["saved"])
        self.assertFalse(vs.save(self.r, "a.md", T0)["saved"])                  # 同じ内容は足さない
        self.n.write_text("v2\n", encoding="utf-8")
        self.assertTrue(vs.save(self.r, "a.md", T0)["saved"])                   # 同じ秒でも順序が崩れない
        v = vs.list_versions(self.r, "a.md")["versions"]
        self.assertEqual([x["n"] for x in v], [1, 2])
        self.assertTrue(v[0]["same_as_current"] and not v[1]["same_as_current"])
        self.assertGreater(v[0]["when"], v[1]["when"])
        self.n.write_text("v1\n", encoding="utf-8")                              # 古い版と同じ内容でも、直前と違えば足す
        self.assertTrue(vs.save(self.r, "a.md", T0)["saved"])
        self.assertEqual(len(vs.list_versions(self.r, "a.md")["versions"]), 3)

    def test_diff_and_restore_is_undoable(self):
        vs.save(self.r, "a.md", T0)
        self.n.write_text("v2\nextra\n", encoding="utf-8")
        d = vs.diff(self.r, "a.md", 1)
        self.assertFalse(d["identical"])
        self.assertIn("+extra", d["diff"])
        r = vs.restore(self.r, "a.md", 1, T0)
        self.assertTrue(r["restored"] and r["kept_current"])
        self.assertEqual(self.n.read_text(encoding="utf-8"), "v1\n")
        self.assertEqual(len(vs.list_versions(self.r, "a.md")["versions"]), 2)    # 戻す前の内容が残った
        vs.restore(self.r, "a.md", 1, T0)                                         # 版 1 = 戻す前の内容。戻したものをさらに戻せる
        self.assertEqual(self.n.read_text(encoding="utf-8"), "v2\nextra\n")

    def test_restore_same_and_bad_numbers(self):
        vs.save(self.r, "a.md", T0)
        self.assertFalse(vs.restore(self.r, "a.md", 1)["restored"])                # 今と同じなら何もしない
        for n in (0, 2, -1):
            with self.assertRaises(ValueError):
                vs.restore(self.r, "a.md", n)
        (self.r / "b.md").write_text("x", encoding="utf-8")
        with self.assertRaises(ValueError):
            vs.diff(self.r, "b.md", 1)                                             # 履歴の無いノート
        self.assertEqual(self.n.read_text(encoding="utf-8"), "v1\n")

    def test_limit_and_paths(self):
        t = T0
        for i in range(vs.MAX_VERSIONS + 5):
            self.n.write_text(f"v{i}\n", encoding="utf-8")
            vs.save(self.r, "a.md", t)
            t += dt.timedelta(seconds=1)
        v = vs.list_versions(self.r, "a.md")["versions"]
        self.assertEqual(len(v), vs.MAX_VERSIONS)
        self.assertEqual(vs.diff(self.r, "a.md", 1)["identical"], True)           # 最新が残る
        for bad in ("../x.md", ".gnosis/x.md", "nope.md", "a.txt"):
            with self.assertRaises(ValueError):
                vs.save(self.r, bad)
        (self.r / "sub").mkdir()
        (self.r / "sub" / "a.md").write_text("other", encoding="utf-8")
        vs.save(self.r, "sub/a.md", T0)                                            # 同じ名前でも別のパスは別の履歴
        self.assertEqual(len(vs.list_versions(self.r, "sub/a.md")["versions"]), 1)
        self.assertEqual(len(vs.list_versions(self.r, "a.md")["versions"]), vs.MAX_VERSIONS)

    def test_cli(self):
        def run(*a):
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                rc = vs.main([str(self.r), *a])
            return rc, buf.getvalue()
        self.assertEqual(run("save", "a.md")[0], 0)
        self.assertIn("# 版の履歴: a.md", run("list", "a.md", "--md")[1])
        self.assertIn("同じ内容です", run("diff", "a.md", "1", "--md")[1])
        self.assertEqual(run("restore", "a.md", "9")[0], 1)
        self.assertEqual(run("bogus", "a.md")[0], 2)


if __name__ == "__main__":
    unittest.main()
