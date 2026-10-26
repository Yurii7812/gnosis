#!/usr/bin/env python3
"""index_migrate.py の試験: Index に直接載っているグループを、Index → ノート → BranchGroup に直す。
一時フォルダ（既定 ~/gnosis-work/test）の vault だけを使う。"""
import os
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import folgezettel as fz  # noqa: E402
import gnosis_graph as gg  # noqa: E402
import index_migrate as im  # noqa: E402


def note(title, time="2026-01-01 00:00:00", attr=False, head=(), body=()):
    s = f"---\ntime: {time}\ntitle: {title}\n" + ("attribute: group\n" if attr else "") + f"---\n\n# {title}\n\n"
    for h, links in head:
        s += h + "\n" + "".join(f"[{t}]({f})\n" for t, f in links) + "\n"
    return s + "".join(b + "\n" for b in body)


class T(unittest.TestCase):
    def setUp(self):
        base = os.environ.get("TMPDIR") or str(Path.home() / "gnosis-work" / "test")
        os.makedirs(base, exist_ok=True)
        self.tmp = tempfile.TemporaryDirectory(dir=base)
        self.bk = tempfile.TemporaryDirectory(dir=base)
        r = self.r = Path(self.tmp.name).resolve()
        (r / "index.md").write_text(note("Index", attr=True, body=["[A語](ga.md)", "[B語](gb.md)", "[C語](gc.md)", "[普通](plain.md)"]))
        # A: 古い n1 と新しい n2。持ち主なし
        (r / "ga.md").write_text(note("A索引", attr=True, head=[("Group:", [("Index", "index.md")])], body=["[新しい](n2.md)", "[古い](n1.md)"]))
        (r / "n1.md").write_text(note("古いノート", time="2026-01-01 00:00:00", head=[("Group:", [("A", "ga.md")])]))
        (r / "n2.md").write_text(note("新しいノート", time="2026-03-01 00:00:00", head=[("Group:", [("A", "ga.md")])]))
        # B: 持ち主 o1 が既にいる（古いメンバーは別）
        (r / "gb.md").write_text(note("B索引", attr=True, head=[("Group:", [("Index", "index.md")])], body=["[古いb](n3.md)"]))
        (r / "o1.md").write_text(note("持ち主", time="2026-05-01 00:00:00", head=[("BranchGroup:", [("B索引", "gb.md")])]))
        (r / "n3.md").write_text(note("古いbノート", time="2025-01-01 00:00:00", head=[("Group:", [("B", "gb.md")])]))
        # C: 項目 n4 には既に別の親 p がある
        (r / "gc.md").write_text(note("C索引", attr=True, head=[("Group:", [("Index", "index.md")])], body=["[四](n4.md)", "[五](n5.md)"]))
        (r / "p.md").write_text(note("別の親", body=["[四](n4.md)"]))
        (r / "n4.md").write_text(note("四ノート", time="2026-02-01 00:00:00", head=[("ParentBranch:", [("別の親", "p.md")]), ("Group:", [("C", "gc.md")])]))
        (r / "n5.md").write_text(note("五ノート", time="2026-02-02 00:00:00", head=[("Group:", [("C", "gc.md")])]))
        (r / "plain.md").write_text(note("普通のノート"))

    def tearDown(self):
        self.tmp.cleanup()
        self.bk.cleanup()

    def test_plan(self):
        p = {x["group"]: x for x in im.plan(self.r)}
        self.assertEqual(set(p), {"ga.md", "gb.md", "gc.md"})
        self.assertEqual(p["ga.md"]["entry"], "n1.md")          # いちばん古いメンバー
        self.assertEqual(p["gb.md"]["entry"], "o1.md")          # 持ち主が既にいる
        self.assertEqual(p["gc.md"]["entry"], "n4.md")          # 4/5 のうち古い方
        self.assertEqual(p["ga.md"]["children"], ["n2.md"])
        self.assertEqual([s["note"] for s in p["gc.md"]["skipped"]], [])  # n4 が最初のノートなので子は n5 だけ
        self.assertEqual(p["gc.md"]["children"], ["n5.md"])

    def test_apply(self):
        res = im.apply(self.r, self.bk.name, allow_open=True)
        self.assertTrue(res["ok"], res)
        self.assertTrue(Path(res["backup"]).exists())
        idx = (self.r / "index.md").read_text()
        self.assertIn("[A語](n1.md)", idx)   # 索引語はそのまま、行先が最初のノートに
        self.assertIn("[B語](o1.md)", idx)
        self.assertNotIn("](ga.md)", idx)
        n1 = (self.r / "n1.md").read_text()
        self.assertIn("BranchGroup:", n1)
        self.assertIn("(ga.md)", n1)
        g = gg.build(self.r)
        # 最初のノートは Index の下の最上位として番号が付き、BranchGroup のグループは同じ番号
        self.assertTrue(g.nodes["n1.md"].fz)
        self.assertEqual(g.nodes["ga.md"].fz, g.nodes["n1.md"].fz)
        # 項目は最初のノートの Branch の子（番号は親の下）
        self.assertIn(("n1.md", "parent_branch"), [(e.dst, e.kind) for e in g.edges if e.src == "n2.md"])
        self.assertTrue(g.nodes["n2.md"].fz.startswith(g.nodes["n1.md"].fz))
        # Index は グループ を直接持たない
        direct = [e.dst for e in g.edges if e.src == "index.md" and e.kind == "link" and g.nodes[e.dst].is_group]
        self.assertEqual(direct, [])
        # もう直すものは無い
        self.assertEqual([x for x in im.plan(self.r) if x["entry"]], [])
        self.assertEqual(res["check_before"].get("broken_links"), res["check_after"].get("broken_links"))

    def test_refuses_when_open(self):
        """vault のファイルを Vim が開いているときは、何も書かずに断る。"""
        import subprocess
        child = subprocess.Popen(["bash", "-c", 'exec -a "vim ' + str(self.r) + '/n1.md" sleep 20'])
        try:
            import time
            time.sleep(0.3)
            res = im.apply(self.r, self.bk.name)
            self.assertFalse(res["ok"])
            self.assertTrue(res["open"])
            self.assertIn("](ga.md)", (self.r / "index.md").read_text())  # 何も書いていない
            self.assertEqual(list(Path(self.bk.name).iterdir()), [])      # バックアップも作らない
        finally:
            child.kill()
            child.wait()


if __name__ == "__main__":
    unittest.main()
