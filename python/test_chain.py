#!/usr/bin/env python3
import contextlib
import datetime as dt
import hashlib
import io
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import chain as ch


def note(root, name, title, body=""):
    p = root / name
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(f"---\ntime: 2026-01-01 00:00:00\ntitle: {title}\n---\n\n# {title}\n\n{body}\n", encoding="utf-8")


def md5(root):
    return {str(p.relative_to(root)): hashlib.md5(p.read_bytes()).hexdigest() for p in root.rglob("*") if p.is_file() and ".gnosis" not in p.parts and ".state" not in p.parts}


class ChainTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(dir=str(Path.home() / "gnosis-work" / "test"))
        self.addCleanup(self.tmp.cleanup)
        r = self.root = Path(self.tmp.name)
        note(r, "h1.md", "ハーブ1", "水やりのコツ")
        note(r, "h2.md", "ハーブ2", "水やりと日当たり")
        note(r, "sub/h3.md", "ハーブ3", "水やりの失敗")
        note(r, "other.md", "別の話", "料理のこと")
        note(r, "hub.md", "ハブ", "まとめ\n\nRelated:\n[ハーブ1](h1.md)\n")
        self.before = md5(r)

    def test_parse_pick(self):
        self.assertEqual(ch.parse_pick(None, 4), [1, 2, 3, 4])
        self.assertEqual(ch.parse_pick("1,3-4", 5), [1, 3, 4])
        self.assertEqual(ch.parse_pick("2,2,1-2", 5), [2, 1])                           # 重複は 1 回
        for bad in ("0", "6", "3-1", "a", "1,,2", "1-", "-1"):
            with self.assertRaises(ValueError, msg=bad):
                ch.parse_pick(bad, 5)

    def test_add_related_creates_block_extends_and_dedupes(self):
        t = "# N\n\n本文\n"
        out, added = ch.add_related(t, "n.md", [("A", "a.md"), ("B", "sub/b.md"), ("自分", "n.md")])
        self.assertEqual(out, "# N\n\n本文\n\nRelated:\n[A](a.md)\n[B](sub/b.md)\n")       # 無ければ末尾に作る・自分自身は足さない
        self.assertEqual(added, ["a.md", "sub/b.md"])
        t2 = "# N\n\nRelated:\n[A](a.md)\n\n続き\n"
        out2, added2 = ch.add_related(t2, "n.md", [("A", "a.md"), ("C", "c.md")])
        self.assertEqual(out2, "# N\n\nRelated:\n[A](a.md)\n[C](c.md)\n\n続き\n")           # 既存のブロックの最後に足す・既にあるものは足さない
        self.assertEqual(added2, ["c.md"])
        self.assertEqual(ch.add_related(t2, "n.md", [("A", "a.md")]), (t2, []))             # 足すものが無ければ不変
        fenced = "# N\n\n```\nRelated:\n[X](x.md)\n```\n"
        out3, _ = ch.add_related(fenced, "n.md", [("A", "a.md")])
        self.assertTrue(out3.startswith(fenced.rstrip("\n")))                               # コードブロックの中の Related: は見ない
        self.assertTrue(out3.endswith("Related:\n[A](a.md)\n"))
        # 別フォルダのノートからの相対パス・空白の符号化
        out4, _ = ch.add_related("# N\n", "sub/n.md", [("T", "top.md"), ("S", "sub/x y.md")])
        self.assertEqual(out4, "# N\n\nRelated:\n[T](../top.md)\n[S](x%20y.md)\n")
        # %20 で書かれた既存リンクも同じ相手として扱う
        out5, added5 = ch.add_related("# N\n\nRelated:\n[S](x%20y.md)\n", "n.md", [("S", "x y.md")])
        self.assertEqual(added5, [])

    def test_dry_run_changes_nothing_and_shows_what_would_happen(self):
        p = ch.plan(self.root, "related", "水やり", "hub.md")
        self.assertEqual([r["path"] for r in p["results"]].count("h1.md"), 1)
        self.assertEqual(set(p["will_add"]), {"h2.md", "sub/h3.md"})                        # h1 はすでにある
        self.assertEqual(p["skipped"], ["h1.md"])
        self.assertTrue(any("ハーブ2" in x for x in p["preview"]))
        self.assertEqual(self.before, md5(self.root))                                       # 試走は何も書かない
        pi = ch.plan(self.root, "index", "水やり", "idx.md")
        self.assertEqual(len(pi["preview"]), 3)
        self.assertFalse((self.root / "idx.md").exists())

    def test_apply_related_then_undo_restores_exactly(self):
        r = ch.apply(self.root, "related", "水やり", "hub.md")
        self.assertTrue(r["applied"])
        text = (self.root / "hub.md").read_text(encoding="utf-8")
        self.assertIn("[ハーブ2](h2.md)", text)
        self.assertIn("[ハーブ3](sub/h3.md)", text)
        self.assertEqual(text.count("[ハーブ1](h1.md)"), 1)                                 # 重複しない
        u = ch.undo(self.root)
        self.assertTrue(u["ok"])
        self.assertEqual(md5(self.root), self.before)                                        # 完全に元通り
        self.assertFalse(ch.undo(self.root)["ok"])                                           # 2 回目は取り消すものがない

    def test_pick_limits_the_set(self):
        res = ch.plan(self.root, "related", "水やり", "hub.md")["results"]
        n_h3 = next(x["n"] for x in res if x["path"] == "sub/h3.md")
        r = ch.apply(self.root, "related", "水やり", "hub.md", str(n_h3))
        self.assertEqual(r["added"], ["sub/h3.md"])
        self.assertNotIn("ハーブ2", (self.root / "hub.md").read_text(encoding="utf-8"))

    def test_undo_refuses_after_later_edit_unless_forced(self):
        ch.apply(self.root, "related", "水やり", "hub.md")
        (self.root / "hub.md").write_text("手で書き換えた\n", encoding="utf-8")
        u = ch.undo(self.root)
        self.assertFalse(u["ok"])
        self.assertEqual((self.root / "hub.md").read_text(encoding="utf-8"), "手で書き換えた\n")   # 手で直した内容を勝手に消さない
        self.assertTrue(ch.undo(self.root, force=True)["ok"])

    def test_apply_index_writes_new_note_only(self):
        r = ch.apply(self.root, "index", "水やり", "idx/水やり索引.md", now=dt.datetime(2026, 10, 21, 9, 0, 0))
        text = (self.root / "idx" / "水やり索引.md").read_text(encoding="utf-8")
        self.assertTrue(text.startswith("---\ntime: 2026-10-21 09:00:00\ntitle: 水やりの索引（案）\nmoc: true\n---\n"))
        self.assertIn("[ハーブ3](../sub/h3.md)", text)                                       # 書き出し先からの相対パス
        self.assertEqual(r["count"], 3)
        self.assertNotIn("attribute", text)
        with self.assertRaises(ValueError) as cm:
            ch.apply(self.root, "index", "水やり", "idx/水やり索引.md")
        self.assertIn("上書きしません", str(cm.exception))

    def test_refusals_change_nothing(self):
        cases = [(("related", "水やり", "../out.md"), "vault の外"), (("related", "水やり", ".state/x.md"), "ドット"), (("related", "水やり", "none.md"), "ありません"),
                 (("related", "水やり", "x.txt"), ".md"), (("index", "水やり", "hub.md"), "上書きしません"), (("related", "存在しない語", "hub.md"), "検索結果がありません"),
                 (("related", "   ", "hub.md"), "検索の語"), (("zzz", "水やり", "hub.md"), "index か related")]
        for args, msg in cases:
            with self.assertRaises(ValueError, msg=str(args)) as cm:
                ch.apply(self.root, *args)
            self.assertIn(msg, str(cm.exception))
        with self.assertRaises(ValueError):
            ch.apply(self.root, "related", "水やり", "hub.md", "99")
        self.assertEqual(self.before, md5(self.root))

    def test_nothing_to_add(self):
        r = ch.apply(self.root, "related", "ハーブ1", "hub.md")                              # 検索結果は h1 だけ・すでにある
        self.assertFalse(r["applied"])
        self.assertIn("足すリンクがありません", r["reason"])
        self.assertEqual(self.before, md5(self.root))

    def test_cli(self):
        def run(*a):
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                rc = ch.main([str(self.root), *a])
            return rc, buf.getvalue()
        self.assertIn("試走。何も書いていません", run("related", "水やり", "hub.md", "--md")[1])
        self.assertEqual(self.before, md5(self.root))
        self.assertIn("書きました", run("related", "水やり", "hub.md", "--apply", "--md")[1])
        self.assertEqual(run("undo")[0], 0)
        self.assertEqual(run("undo")[0], 1)
        self.assertEqual(run("index", "水やり", "i.md", "--apply", "--pick", "1-2")[0], 0)
        self.assertEqual(run("index", "水やり", "i2.md", "--pick", "x")[0], 1)
        self.assertEqual(run("bogus")[0], 2)


if __name__ == "__main__":
    unittest.main()
