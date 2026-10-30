#!/usr/bin/env python3
"""曼荼羅のキャッシュ（mandala_cache.py）の試験。mandala_view.dump と同じ内容になること・差分更新が効くこと。
一時フォルダ（既定 ~/gnosis-work/test）の vault だけを使う。"""
import os
import sys
import tempfile
import time
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import mandala_cache as mc  # noqa: E402
import mandala_view as mv  # noqa: E402
from test_mandala_view import note  # noqa: E402


class T(unittest.TestCase):
    def setUp(self):
        base = os.environ.get("TMPDIR") or str(Path.home() / "gnosis-work" / "test")
        os.makedirs(base, exist_ok=True)
        self.tmp = tempfile.TemporaryDirectory(dir=base)
        self.r = r = Path(self.tmp.name)
        (r / "index.md").write_text(note("Index", body=["[植物](plant.md)", "[料理](cook.md)", "[壊れた](nothing.md)"]))
        (r / "plant.md").write_text(note("植物", True, [("Index", "index.md")], ["[ハーブ](herb.md)", "[香草](herb.md)", "[栽培](grow.md)", "[下位](sub.md)"]))
        (r / "cook.md").write_text(note("料理", True, [("Index", "index.md")], ["[ハーブ](herb.md)"]))
        (r / "sub.md").write_text(note("下位", True, [("植物", "plant.md")]))
        (r / "herb.md").write_text(note("ハーブ", False, [("植物", "plant.md"), ("料理", "cook.md")], ["[栽培](grow.md)", "[自分](herb.md)"]))
        (r / "grow.md").write_text(note("栽培", False, [("植物", "plant.md")]))
        (r / "dir").mkdir()
        (r / "dir" / "deep.md").write_text(note("深い", False, [("植物", "../plant.md")], ["[栽培](../grow.md)"]))
        (r / ".hidden").mkdir()
        (r / ".hidden" / "x.md").write_text(note("隠し"))

    def tearDown(self):
        self.tmp.cleanup()

    def same_as_dump(self):
        d = mv.dump(self.r)["nodes"]
        for rel, want in d.items():
            got = mc.node(self.r, rel)
            self.assertIsNotNone(got, rel)
            self.assertEqual(got["t"], want["t"], rel)
            self.assertEqual(got["g"], want["g"], rel)
            self.assertEqual(got["o"], want["o"], rel)
            self.assertEqual(got.get("r"), want.get("r"), rel)
            self.assertEqual(got.get("en"), want.get("en"), rel)
        self.assertEqual(mc.status(self.r)["notes"], len(d))

    def test_same_as_dump(self):
        mc.refresh(self.r)
        self.same_as_dump()
        self.assertIsNone(mc.node(self.r, ".hidden/x.md"))

    def test_ring_has_light_neighbors(self):
        mc.refresh(self.r)
        rg = mc.ring(self.r, "herb.md")["nodes"]
        self.assertIn("o", rg["herb.md"])
        self.assertEqual(rg["plant.md"], {"t": "植物", "g": 1})
        self.assertEqual(rg["grow.md"]["g"], 0)

    def test_nodes_batch(self):
        mc.refresh(self.r)
        d = mc.nodes(self.r, ["herb.md", "grow.md"])["nodes"]
        self.assertIn("o", d["herb.md"])
        self.assertIn("o", d["grow.md"])
        self.assertEqual(d["plant.md"], {"t": "植物", "g": 1})

    def test_incremental(self):
        mc.refresh(self.r)
        (self.r / "grow.md").write_text(note("栽培", False, [("料理", "cook.md")]))
        (self.r / "new.md").write_text(note("新しい", False, [("植物", "plant.md")]))
        (self.r / "sub.md").unlink()
        r = mc.refresh(self.r, force=True)
        self.assertEqual((r["changed"], r["removed"]), (2, 1))
        self.same_as_dump()
        self.assertIsNone(mc.node(self.r, "sub.md"))

    def test_only_on_save(self):
        mc.refresh(self.r)
        (self.r / "herb.md").write_text(note("ハーブ改", False, [("料理", "cook.md")]))
        r = mc.refresh(self.r, only=["herb.md"])
        self.assertEqual(r["changed"], 1)
        self.assertEqual(mc.node(self.r, "herb.md")["t"], "ハーブ改")
        (self.r / "herb.md").unlink()
        r = mc.refresh(self.r, only=["herb.md"])
        self.assertEqual(r["removed"], 1)
        self.assertIsNone(mc.node(self.r, "herb.md"))

    def test_only_ignores_dot_dirs(self):
        # \e の展開結果（.trash/T_*.md）を右の窓で開いても、曼荼羅のノートとして取り込まない
        mc.refresh(self.r)
        (self.r / ".trash").mkdir()
        (self.r / ".trash" / "T_1.md").write_text(note("展開: Index", False, [("Index", "../index.md")]))
        r = mc.refresh(self.r, only=[".trash/T_1.md"])
        self.assertEqual(r["changed"], 0)
        self.assertIsNone(mc.node(self.r, ".trash/T_1.md"))

    def test_content_similarity_rank_and_incremental_update(self):
        r = self.r
        (r / "herb.md").write_text(note("ハーブ栽培", False, [],
            ["ハーブの栽培には土壌と水やりの工夫が必要"], "1a"))
        (r / "matched.md").write_text(note("ハーブ栽培と水やり", False, [],
            ["水やりと土壌を研究する"], "900"))
        (r / "number.md").write_text(note("無関係な数学", False, [],
            ["数学の数列と論理演算"], "1a1"))
        (r / "diary.md").write_text(note("2026-10-30", False, [],
            ["ハーブの栽培と土壌と水やり"], "1a2"))
        mc.refresh(r, full=True)
        ids = [d["id"] for d in mc.related(r, "herb.md")]
        self.assertIn("matched.md", ids)
        self.assertNotIn("number.md", ids)
        self.assertNotIn("diary.md", ids)
        self.assertNotIn("index.md", ids)
        # w rank uses the same content scores, even with body=False.
        rank = {d["id"]: d["score"] for d in mc.related(r, "herb.md", body=False)}
        self.assertGreater(rank["matched.md"], 0)
        self.assertNotIn("diary.md", rank)
        (r / "matched.md").write_text(note("全く異なる話", False, [],
            ["機械工学とエンジンの部品"]))
        mc.refresh(r, only=["matched.md"])
        self.assertNotIn("matched.md", [d["id"] for d in mc.related(r, "herb.md")])

    def test_skip_recent_full_scan(self):
        mc.refresh(self.r)
        mc.FULL_FLOOR = 3600; self.assertTrue(mc.refresh(self.r).get("skipped"))
        self.assertFalse(mc.refresh(self.r, force=True).get("skipped"))

    def test_find_groups(self):
        mc.refresh(self.r)
        self.assertEqual(mc.find(self.r, ["料"]), ["cook.md"])
        self.assertEqual(mc.find(self.r, ["ハーブ"]), [])   # 索引ではない

    def test_cache_is_not_synced(self):
        mc.refresh(self.r)
        self.assertEqual((self.r / ".gnosis" / "cache" / ".gitignore").read_text().strip(), "*")


    def test_big_vault_near_related_search(self):
        mc.refresh(self.r)
        self.assertFalse(mc.is_big(self.r))
        old = mc.BIG_VAULT
        mc.BIG_VAULT = 2
        try:
            self.assertTrue(mc.is_big(self.r))
            # herb は 植物 と 料理 に載っている。栽培 は 植物 だけ → 栽培 に近い索引: 料理（同じ植物に載っている herb が料理にも）
            near = mc.near(self.r, "grow.md")
            self.assertIn("cook.md", [d["id"] for d in near])
            self.assertNotIn("plant.md", [d["id"] for d in near])   # すでに所属している索引は出さない
            rel = mc.related(self.r, "herb.md")
            ids = [d["id"] for d in rel]
            self.assertIn("plant.md", ids)
            self.assertIn("grow.md", ids)
            self.assertEqual(mc.search(self.r, ["ハーブ"])[:1], ["herb.md"])   # 題に合うものが先
        finally:
            mc.BIG_VAULT = old


    def test_old_schema_cache_is_rebuilt(self):
        """古い版のキャッシュ（スキーマ 3。fz の列と ttok が無い）があっても、落ちずに作り直す。"""
        import sqlite3
        d = self.r / ".gnosis" / "cache"
        d.mkdir(parents=True)
        db = sqlite3.connect(str(d / "mandala.sqlite"))
        db.executescript("""
            CREATE TABLE meta(k TEXT PRIMARY KEY, v TEXT);
            CREATE TABLE files(id INTEGER PRIMARY KEY, path TEXT UNIQUE, name TEXT, stem TEXT, mtime INTEGER, size INTEGER, title TEXT, g INTEGER);
            CREATE TABLE edges(src INTEGER, kind INTEGER, dst INTEGER);
            CREATE TABLE ents(grp INTEGER, dst INTEGER, name TEXT);
            INSERT INTO meta VALUES('schema', '3');
            INSERT INTO files(path,name,stem,mtime,size,title,g) VALUES('old.md','old.md','old',1,1,'古い',0);
        """)
        db.commit()
        db.close()
        self.assertEqual(mc.status(self.r)["notes"], 0)     # 読むだけの呼び出しは落ちず、空に見える
        mc.refresh(self.r)
        self.same_as_dump()
        self.assertIsNone(mc.node(self.r, "old.md"))


if __name__ == "__main__":
    unittest.main()
