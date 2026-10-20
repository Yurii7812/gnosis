#!/usr/bin/env python3
import contextlib
import datetime as dt
import hashlib
import io
import os
import sys
import tempfile
import time
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import explore as ex


def note(root, name, title, body=""):
    (root / name).write_text(f"---\ntime: 2026-01-01 00:00:00\ntitle: {title}\n---\n\n# {title}\n\n{body}\n", encoding="utf-8")


class ExploreTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(dir=str(Path.home() / "Desktop" / "test"))
        self.addCleanup(self.tmp.cleanup)
        r = self.root = Path(self.tmp.name)
        # 鎖: a - b - c - d - e（リンク）。f は a とつながらないが内容が近い。g は孤立。
        note(r, "a.md", "ハーブの水やり", "[b](b.md)\nハーブは乾燥した土を好み水やりは控えめにする")
        note(r, "b.md", "土の話", "[a](a.md) [c](c.md)\n土の水はけについて")
        note(r, "c.md", "道具", "[b](b.md) [d](d.md)\nじょうろとスコップ")
        note(r, "d.md", "買い物", "[c](c.md) [e](e.md)\n店の一覧")
        note(r, "e.md", "家計", "[d](d.md)\n支出の記録")
        note(r, "f.md", "ローズマリーの育て方", "ハーブは乾燥した土を好み水やりは控えめにする。ローズマリーも同じ")
        note(r, "g.md", "孤立したメモ", "だれともつながっていない")
        old = time.time() - 800 * 86400
        for n in ("c.md", "g.md", "f.md"):
            os.utime(r / n, (old, old))
        self.before = {p.name: hashlib.md5(p.read_bytes()).hexdigest() for p in r.glob("*.md")}

    def same(self):
        self.assertEqual(self.before, {p.name: hashlib.md5(p.read_bytes()).hexdigest() for p in self.root.glob("*.md")})

    def test_walk_follows_links_only_and_is_reproducible(self):
        w1 = ex.random_walk(self.root, "a.md", 4, seed=7)
        w2 = ex.random_walk(self.root, "a.md", 4, seed=7)
        self.assertEqual(w1, w2)                                              # 同じ seed なら同じ散歩
        names = [p["path"] for p in w1["path"]]
        order = "abcde"
        for x, y in zip(names, names[1:]):
            self.assertEqual(abs(order.index(x[0]) - order.index(y[0])), 1, names)   # 隣のノートへだけ進む
        self.assertEqual(w1["steps"], 4)
        self.assertNotIn("f.md", names)
        self.assertNotIn("g.md", names)
        # 孤立ノートから始めると行き止まりで止まる
        w = ex.random_walk(self.root, "g.md", 5, seed=1)
        self.assertEqual(w["steps"], 0)
        self.assertIn("行き止まり", w["stopped"])
        # 未訪問を優先: 5 歩あれば鎖の端まで届く seed がある（少なくとも訪問数 > 2）
        self.assertGreaterEqual(ex.random_walk(self.root, "a.md", 4, seed=3)["distinct"], 3)
        with self.assertRaises(ValueError):
            ex.random_walk(self.root, "zzz.md")
        self.same()

    def test_roulette_modes(self):
        self.assertEqual(ex.roulette(self.root, "orphan", seed=1)["note"]["path"], "g.md" if False else ex.roulette(self.root, "orphan", seed=1)["note"]["path"])
        orphans = {ex.roulette(self.root, "orphan", seed=s)["note"]["path"] for s in range(10)}
        self.assertEqual(orphans, {"f.md", "g.md"})                         # リンクを持たないのは f と g
        old = {ex.roulette(self.root, "old", seed=s)["note"]["path"] for s in range(20)}
        self.assertTrue(old <= {"c.md", "g.md", "f.md"})
        self.assertEqual(ex.roulette(self.root, "any", seed=5), ex.roulette(self.root, "any", seed=5))
        with self.assertRaises(ValueError):
            ex.roulette(self.root, "nope")
        self.same()

    def test_serendipity_finds_close_but_far(self):
        s = ex.serendipity(self.root, "a.md")
        self.assertEqual(s["candidates"][0]["path"], "f.md")
        self.assertIsNone(s["candidates"][0]["distance"])                   # つながっていない
        self.assertIn("つながっていない", s["candidates"][0]["why"])
        self.assertNotIn("b.md", [x["path"] for x in s["candidates"]])      # 隣は意外ではない
        self.assertIn("偶然", s["note_text"])
        self.same()

    def test_archaeology_reasons(self):
        a = ex.archaeology(self.root, 365, dt.date.today())
        by = {x["path"]: x for x in a["rediscover"]}
        self.assertIn("f.md", by)                                            # 古いが、最近の a.md と内容が近い
        self.assertTrue(any("内容が近い" in r for r in by["f.md"]["reasons"]))
        self.assertIn("c.md", by)                                            # 古いが、最近更新した b.md から今もリンクされている
        self.assertTrue(any("リンクされている" in r for r in by["c.md"]["reasons"]))
        self.assertNotIn("g.md", by)                                         # 古くて孤立・無関係なものは根拠が無いので出さない
        self.assertEqual(ex.archaeology(self.root, 5000)["rediscover"], [])
        self.same()

    def test_between(self):
        r = ex.between(self.root, "a.md", "d.md")
        self.assertEqual(r["link_path"], ["ハーブの水やり", "土の話", "道具", "買い物"])
        self.assertEqual([v["path"] for v in r["via_links"]], ["b.md", "c.md"])
        self.assertIsNone(ex.between(self.root, "a.md", "g.md")["link_path"])
        self.assertTrue(ex.between(self.root, "a.md", "f.md")["shared_terms"])
        self.assertNotIn("a.md", [x["path"] for x in r["close_to_both"]])
        with self.assertRaises(ValueError):
            ex.between(self.root, "a.md", "nope")
        self.same()

    def test_cli_and_markdown(self):
        def run(*a):
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                rc = ex.main([str(self.root), *a])
            return rc, buf.getvalue()
        self.assertIn("# 散歩（seed 7）", run("walk", "a.md", "--steps", "3", "--seed", "7", "--md")[1])
        self.assertIn("# ルーレット", run("roulette", "orphan", "--seed", "1", "--md")[1])
        self.assertIn("# 意外な近さ", run("serendipity", "a.md", "--md")[1])
        self.assertIn("# 知識考古学", run("archaeology", "--md")[1])
        self.assertIn("## リンクの経路", run("between", "a.md", "d.md", "--md")[1])
        self.assertEqual(run("walk", "zzz.md")[0], 1)
        self.assertEqual(run("bogus")[0], 2)
        self.same()


if __name__ == "__main__":
    unittest.main()
