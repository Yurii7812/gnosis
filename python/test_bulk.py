#!/usr/bin/env python3
import contextlib, datetime as dt, io, sys, tempfile, unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import bulk

T = dt.datetime(2026, 10, 21, 10, 0, 0)


class T_(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory(dir=str(Path.home() / "gnosis-work" / "test"))
        self.addCleanup(tmp.cleanup)
        self.r = Path(tmp.name)
        for n in ("a", "b", "c"):
            (self.r / f"{n}.md").write_text(f"{n}1\n{n}2\n", encoding="utf-8")
        (self.r / "sub").mkdir()
        (self.r / "sub" / "d.md").write_text("d\n", encoding="utf-8")

    def op(self):
        """典型的な一括変更: 変える・増やす・消す・触るが内容は同じ。"""
        (self.r / "a.md").write_text("a1\nA2 changed\nnew\n", encoding="utf-8")
        (self.r / "new.md").write_text("new\n", encoding="utf-8")
        (self.r / "b.md").unlink()
        (self.r / "c.md").write_text("c1\nc2\n", encoding="utf-8")          # 書き直したが同じ

    def test_cycle_and_undo(self):
        t = bulk.begin(self.r, "テスト", T)["id"]
        self.op()
        e = bulk.end(self.r, t)
        self.assertEqual((e["modified"], e["added"], e["deleted"]), (1, 1, 1))
        s = bulk.status(self.r)
        self.assertEqual(s["modified"], [{"path": "a.md", "added_lines": 2, "removed_lines": 1}])
        self.assertIn("a.md", bulk.to_md("status", s))
        u = bulk.undo(self.r)
        self.assertTrue(u["undone"])
        self.assertEqual((u["restored"], u["removed"]), (2, 1))
        self.assertEqual((self.r / "a.md").read_text(encoding="utf-8"), "a1\na2\n")
        self.assertEqual((self.r / "b.md").read_text(encoding="utf-8"), "b1\nb2\n")
        self.assertFalse((self.r / "new.md").exists())
        with self.assertRaises(ValueError):
            bulk.undo(self.r)                                               # 取り消しは 1 回だけ

    def test_conflict_needs_force(self):
        t = bulk.begin(self.r, "x", T)["id"]
        self.op()
        bulk.end(self.r, t)
        (self.r / "a.md").write_text("手で書き足した\n", encoding="utf-8")
        (self.r / "b.md").write_text("再び作った\n", encoding="utf-8")
        u = bulk.undo(self.r)
        self.assertFalse(u["undone"])
        self.assertEqual(u["conflicts"], ["a.md", "b.md"])
        self.assertEqual((self.r / "a.md").read_text(encoding="utf-8"), "手で書き足した\n")      # 何も変えていない
        self.assertTrue((self.r / "new.md").exists())
        u = bulk.undo(self.r, force=True)
        self.assertTrue(u["undone"] and u["forced"])
        self.assertEqual((self.r / "a.md").read_text(encoding="utf-8"), "a1\na2\n")

    def test_hidden_ignored_and_keep_limit_and_errors(self):
        (self.r / ".gnosis").mkdir(exist_ok=True)
        (self.r / ".gnosis" / "x.md").write_text("hidden", encoding="utf-8")
        t = bulk.begin(self.r, "h", T)["id"]
        (self.r / ".gnosis" / "x.md").write_text("changed", encoding="utf-8")
        self.assertEqual(bulk.end(self.r, t)["modified"], 0)                 # ドット始まりは対象外
        for i in range(1, 8):
            bulk.end(self.r, bulk.begin(self.r, f"n{i}", T + dt.timedelta(seconds=i))["id"])
        self.assertEqual(len(bulk.list_tx(self.r)["transactions"]), bulk.KEEP)
        self.assertEqual(bulk.list_tx(self.r)["transactions"][0]["label"], "n7")
        with self.assertRaises(ValueError):
            bulk.status(self.r, "nope")
        o = bulk.begin(self.r, "open", T + dt.timedelta(seconds=99))["id"]
        with self.assertRaises(ValueError):
            bulk.undo(self.r, o)                                             # 終わっていない取引
        with self.assertRaises(ValueError):
            bulk.status(Path(tempfile.mkdtemp(dir=str(Path.home() / "gnosis-work" / "test"))))

    def test_cli(self):
        def run(*a):
            b = io.StringIO()
            with contextlib.redirect_stdout(b):
                rc = bulk.main([str(self.r), *a])
            return rc, b.getvalue()
        self.assertEqual(run("begin", "cli")[0], 0)
        tid = bulk.list_tx(self.r)["transactions"][0]["id"]
        self.assertEqual(run("end", tid)[0], 0)
        self.assertIn("# 一括変更: cli", run("status", "--md")[1])
        self.assertIn("一括変更の記録", run("list", "--md")[1])
        self.assertEqual(run("undo", "nope")[0], 1)
        self.assertEqual(run("bogus")[0], 2)


if __name__ == "__main__":
    unittest.main()
