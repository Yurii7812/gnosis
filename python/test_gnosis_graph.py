#!/usr/bin/env python3
"""gnosis_graph: 型付き有向多重グラフ・壊れたリンク・Folgezettel の見取り図。"""
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import gnosis_graph as gg


def note(root, name, title, body="", fzid="", extra_fm=""):
    fm = f"---\ntime: 2026-01-01 00:00:00\ntitle: {title}\n" + (f'folgezettel: "{fzid}"\n' if fzid else "") + extra_fm + "---\n\n"
    (root / name).write_text(fm + f"# {title}\n\n" + body + "\n", encoding="utf-8")


class GraphTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(dir=str(Path.home() / "Desktop" / "test"))
        self.addCleanup(self.tmp.cleanup)
        r = self.root = Path(self.tmp.name)
        note(r, "index.md", "Index", "[ハーブ](herb.md)\n", extra_fm="attribute: group\n")
        note(r, "herb.md", "ハーブ", "BranchGroup:\n[栽培](grow.md)\n[利用](use.md)\n\n本文から[参考](ref.md)へ。\n", fzid="1")
        note(r, "grow.md", "栽培", "ParentBranch:\n[ハーブ](herb.md)\n\n本文\n", fzid="1a")
        note(r, "use.md", "利用", "ParentBranch:\n[ハーブ](herb.md)\n\nContext:\n[栽培](grow.md)\n\n[壊れた](missing.md)\n", fzid="1b")
        note(r, "ref.md", "参考", "外部[web](https://example.com)と[内部](#h)\n", fzid="2")
        note(r, "lonely.md", "孤立", "だれともつながらない\n")
        note(r, "deep.md", "深い", "", fzid="1a1")
        note(r, "gap.md", "抜け", "", fzid="3a1")        # 3 が無い
        note(r, "dup1.md", "重複A", "", fzid="4")
        note(r, "dup2.md", "重複B", "", fzid="4")
        self.g = gg.build(r)

    def kinds(self, src, dst):
        return sorted(e.kind for e in self.g.edges if e.src == src and e.dst == dst)

    def test_typed_multi_edges(self):
        self.assertIn("branch_group", self.kinds("herb.md", "grow.md"))
        self.assertIn("parent_branch", self.kinds("grow.md", "herb.md"))
        self.assertEqual(self.kinds("herb.md", "ref.md"), ["link"])
        # 同じ 2 ノート間でも種類ごとの別の辺（潰さない）
        self.assertEqual(self.kinds("use.md", "grow.md"), ["context"])
        self.assertIn("folgezettel", self.kinds("grow.md", "herb.md"))
        self.assertIn("parent_branch", self.kinds("grow.md", "herb.md"))

    def test_broken_and_external(self):
        self.assertEqual([(b["src"], b["target"]) for b in self.g.broken], [("use.md", "missing.md")])
        self.assertFalse(any(e.dst.startswith("http") for e in self.g.edges))

    def test_orphans_and_paths(self):
        self.assertIn("lonely.md", self.g.orphans())
        self.assertNotIn("grow.md", self.g.orphans())
        p = self.g.shortest_path("index.md", "grow.md")
        self.assertEqual([n for n, _ in p], ["index.md", "herb.md", "grow.md"])
        self.assertEqual(p[0][1], "")
        self.assertIsNone(self.g.shortest_path("index.md", "lonely.md"))
        # 種類を絞ると、Context でしか届かない経路は通らない
        self.assertIsNone(self.g.shortest_path("use.md", "grow.md", kinds={"link"}))
        self.assertEqual([n for n, _ in self.g.shortest_path("use.md", "grow.md", kinds={"context"})], ["use.md", "grow.md"])

    def test_reachability_is_directed(self):
        r = self.g.reachable("index.md", kinds={"link", "branch_group"})
        self.assertIn("grow.md", r)
        self.assertNotIn("lonely.md", r)
        self.assertNotIn("index.md", self.g.reachable("grow.md", kinds={"branch_group", "link"}))

    def test_folgezettel_navigation_semantics(self):
        i = self.g.fz_info("1a")
        self.assertEqual(i["parent"]["id"], "1")
        self.assertEqual([s["id"] for s in i["siblings"]], ["1a", "1b"])
        self.assertEqual(i["next_sibling"]["id"], "1b")       # 1a → 1b は兄弟（親子ではない）
        self.assertIsNone(i["prev_sibling"])
        self.assertEqual([c["id"] for c in i["children"]], ["1a1"])
        self.assertEqual(i["first_child"]["id"], "1a1")
        self.assertEqual(i["next_in_order"]["id"], "1a1")     # 自然順では 1a の次は 1a1
        self.assertEqual(self.g.fz_info("1b")["prev_in_order"]["id"], "1a1")
        top = self.g.fz_info("1")
        self.assertEqual(top["next_sibling"]["id"], "2")
        self.assertEqual([c["id"] for c in top["children"]], ["1a", "1b"])
        ghost = self.g.fz_info("9")
        self.assertFalse(ghost["exists"])                     # 空き番号は作らず存在しないと返す
        self.assertEqual(self.g.fz_info("3a1")["breadcrumbs"][0]["exists"], False)

    def test_folgezettel_problems_and_tree(self):
        p = self.g.fz_problems()
        self.assertEqual(sorted(p["duplicate_ids"]), ["4"])
        self.assertEqual(p["missing_parents"], ["3", "3a"])  # 3a1 だけがあるので、祖先の 3a と 3 が抜け
        tree = self.g.fz_tree()
        t1 = next(t for t in tree if t["id"] == "1")
        self.assertEqual([c["id"] for c in t1["children"]], ["1a", "1b"])
        self.assertEqual([c["id"] for c in t1["children"][0]["children"]], ["1a1"])
        self.assertEqual([t["id"] for t in tree][:2], ["1", "2"])
        self.assertIn("3a1", [t["id"] for t in tree])         # 親(3)が無い枝も落とさず最上位に出す

    def test_read_only(self):
        before = {p.name: p.read_bytes() for p in self.root.glob("*.md")}
        gg.build(self.root)
        gg.check(self.g)
        self.assertEqual(before, {p.name: p.read_bytes() for p in self.root.glob("*.md")})
        self.assertEqual(list(self.root.glob(".*")), [])      # キャッシュ等を作らない


if __name__ == "__main__":
    unittest.main()
