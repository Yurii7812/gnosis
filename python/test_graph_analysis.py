#!/usr/bin/env python3
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import gnosis_graph as gg
import graph_analysis as ga


def note(root, name, title, body="", fzid="", time_="2026-01-01 00:00:00", extra=""):
    fm = f"---\ntime: {time_}\ntitle: {title}\n" + (f'folgezettel: "{fzid}"\n' if fzid else "") + extra + "---\n\n"
    (root / name).write_text(fm + f"# {title}\n\n" + body + "\n", encoding="utf-8")


def links(*names):
    return " ".join(f"[{n}]({n}.md)" for n in names)


class AnalysisTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(dir=str(Path.home() / "gnosis-work" / "test"))
        self.addCleanup(self.tmp.cleanup)
        r = self.root = Path(self.tmp.name)
        A, B = ["a1", "a2", "a3", "a4"], ["b1", "b2", "b3", "b4"]
        for grp in (A, B):                                       # 2 つの密な領域（全部が互いにリンク）
            for n in grp:
                note(r, n + ".md", n.upper(), links(*[m for m in grp if m != n]))
        note(r, "x.md", "橋", links("a1", "b1"))                  # 2 つの領域をつなぐ
        note(r, "indexA.md", "索引A", links("a1", "a2"), extra="attribute: group\n")
        note(r, "indexB.md", "索引B", links("b1", "x"), extra="attribute: group\n")
        note(r, "c1.md", "循環1", "ParentBranch:\n[循環2](c2.md)\n")                # 階層の循環（不正）
        note(r, "c2.md", "循環2", "ParentBranch:\n[循環1](c1.md)\n")
        note(r, "l1.md", "相互1", links("l2"))                                       # リンクの循環（正常）
        note(r, "l2.md", "相互2", links("l1"))
        note(r, "lonely.md", "孤立", "だれともつながらない")
        # Folgezettel の木と作成日
        note(r, "f1.md", "テーマ", "BranchGroup:\n[深掘り](f1a.md)\n[別の枝](f1b.md)\n", "1", "2026-01-05 00:00:00")
        note(r, "f1a.md", "深掘り", "ParentBranch:\n[テーマ](f1.md)\n", "1a", "2026-01-20 00:00:00")
        note(r, "f1b.md", "別の枝", "ParentBranch:\n[テーマ](f1.md)\n", "1b", "2026-02-02 00:00:00")
        note(r, "f1a1.md", "さらに", "ParentBranch:\n[深掘り](f1a.md)\n", "1a1", "2026-02-10 00:00:00")
        note(r, "f2.md", "別テーマ", "本文", "2", "2026-02-11 00:00:00")
        self.g = gg.build(r)

    def test_hubs_and_kinds(self):
        h = ga.hubs(self.g, 5)
        self.assertEqual(h[0]["degree"], max(x["degree"] for x in h))
        self.assertIn(h[0]["id"], {"a1.md", "b1.md"})                # a1/b1 は領域の中心＋橋からも
        self.assertTrue(all("kinds" in x for x in h))               # 種類別の内訳つき（潰さない）
        k = ga.kinds(self.g)
        self.assertGreater(k["by_kind"]["link"], 20)
        self.assertEqual(k["by_kind"]["parent_branch"], 5)          # c1→c2, c2→c1, f1a→f1, f1b→f1, f1a1→f1a
        self.assertIn("folgezettel", k["by_kind"])
        self.assertGreater(k["derived"], 0)

    def test_central_and_bridges(self):
        top = ga.central(self.g, 6)
        self.assertIn("x.md", [r["id"] for r in top])                   # 橋は媒介中心性が高い
        bx = next(r for r in top if r["id"] == "x.md")["betweenness"]
        self.assertGreater(bx, next(r for r in ga.central(self.g, 40) if r["id"] == "a2.md")["betweenness"])   # 領域の端のノートより高い
        b = ga.bridges(self.g, 10)
        self.assertIn("x.md", [r["id"] for r in b])
        xb = next(r for r in b if r["id"] == "x.md")
        self.assertGreaterEqual(xb["communities_touched"], 2)
        self.assertEqual(ga.betweenness({"p": {"q"}, "q": {"p", "r"}, "r": {"q"}})["q"], 1.0)   # 直線 p-q-r の真ん中

    def test_communities_and_density(self):
        c = ga.communities(self.g)
        mem = c["membership"]
        self.assertEqual(len({mem[n] for n in ("a1.md", "a2.md", "a3.md", "a4.md")}), 1)
        self.assertEqual(len({mem[n] for n in ("b1.md", "b2.md", "b3.md", "b4.md")}), 1)
        self.assertNotEqual(mem["a1.md"], mem["b1.md"])
        self.assertGreater(c["modularity"], 0.2)
        self.assertEqual(ga.communities(self.g)["groups"], c["groups"], "決定的（同じ入力は同じ結果）")
        d = ga.density(self.g)
        a_row = next(r for r in d["communities"] if mem["a1.md"] == r["community"])
        n = a_row["size"]
        self.assertEqual(a_row["density"], round(a_row["internal_edges"] / (n * (n - 1) / 2), 4))   # 密度 = 内部の辺 ÷ 可能な辺
        self.assertGreaterEqual(a_row["density"], 0.7)               # 4 つ全部が互いにリンク（＋索引Aが 2 本）
        self.assertTrue(d["between"])

    def test_islands(self):
        i = ga.islands(self.g)
        self.assertIn("lonely.md", i["isolated"])
        self.assertTrue(any("l1.md" in grp for grp in i["small_groups"]))
        self.assertGreater(i["main_size"], 10)

    def test_reach(self):
        r = ga.reach(self.g, "indexA.md")
        self.assertIn("lonely.md", r["unreached"])
        self.assertNotIn("a3.md", r["unreached"])
        self.assertEqual(r["layers"]["0"], 1)
        self.assertGreaterEqual(r["max_depth"], 1)
        # 索引Bから: 橋を通って A の領域にも届く
        rb = ga.reach(self.g, "索引B")
        self.assertNotIn("a1.md", rb["unreached"])
        with self.assertRaises(ValueError):
            ga.reach(self.g, "nothing.md")

    def test_cycles_distinguish_invalid_from_normal(self):
        c = ga.cycles(self.g)
        self.assertIn(["c1.md", "c2.md"], c["invalid_hierarchy_cycles"])     # 階層の循環は不正
        self.assertFalse(any("l1.md" in x for x in c["invalid_hierarchy_cycles"]))   # リンクの相互参照は不正にしない
        self.assertTrue(any(set(x) == {"l1.md", "l2.md"} for x in c["link_cycles"]))
        self.assertFalse(any("f1.md" in x for x in c["invalid_hierarchy_cycles"]))   # 正しい木は循環ではない

    def test_compare_indexes(self):
        r = ga.compare(self.g, "indexA.md", "indexB.md")
        self.assertGreater(r["a"]["size"], 3)
        self.assertGreater(r["b"]["size"], 3)
        self.assertTrue(set(r["shared"]) & {"a1.md", "x.md", "b1.md"} or r["shared"])   # 橋を通る範囲は重なる
        self.assertTrue(0 < r["jaccard"] <= 1)
        self.assertEqual(r["a"]["layers"]["0"], 1)

    def test_growth_tree(self):
        gr = ga.growth(self.g)
        top = {b["id"]: b for b in gr["branches"]}
        self.assertEqual(top["1"]["size"], 4)                       # 1, 1a, 1a1, 1b
        self.assertEqual(top["1"]["depth"], 3)
        self.assertEqual(top["2"]["size"], 1)
        self.assertEqual(gr["deepest"], 3)
        self.assertEqual(gr["timeline"]["2026-01"]["1"], 2)         # 1 と 1a が 1 月
        self.assertEqual(gr["timeline"]["2026-02"], {"1": 2, "2": 1})
        self.assertEqual(gr["branches"][0]["id"], "1")              # 大きい枝が先

    def test_query_patterns(self):
        q = ga.query(self.g, "?a -[parent_branch]-> ?b")
        pairs = {(r["vars"]["a"], r["vars"]["b"]) for r in q}
        self.assertIn(("f1a.md", "f1.md"), pairs)
        self.assertIn(("c1.md", "c2.md"), pairs)
        q = ga.query(self.g, "?a -[parent_branch]-> ?b{title~テーマ}")                   # 条件つき
        self.assertEqual({r["vars"]["a"] for r in q}, {"f1a.md", "f1b.md"})
        q = ga.query(self.g, "?p <-[parent_branch]- ?c")                                 # 向きを逆に
        self.assertIn(("f1.md", "f1a.md"), {(r["vars"]["p"], r["vars"]["c"]) for r in q})
        q = ga.query(self.g, "?x -[parent_branch]-> ?y -[parent_branch]-> ?z")           # 2 段（孫 → 子 → 親）
        self.assertIn(("f1a1.md", "f1a.md", "f1.md"), {(r["vars"]["x"], r["vars"]["y"], r["vars"]["z"]) for r in q})
        q = ga.query(self.g, "f1.md -[branch_group]-> ?kid")                            # 固定のノートから
        self.assertEqual({r["vars"]["kid"] for r in q}, {"f1a.md", "f1b.md"})
        q = ga.query(self.g, "?a -[link|related]-> x.md")                               # 複数の種類・固定の行き先
        self.assertEqual({r["vars"]["a"] for r in q}, {"indexB.md"})
        self.assertEqual(len(ga.query(self.g, "?a")), len(self.g.nodes))                # ノート 1 つだけのパターンは全ノート
        for bad in ("", "?a -[x]-> ", "?a ?b", "-[link]-> ?b"):
            with self.assertRaises(ValueError):
                ga.query(self.g, bad)
        self.assertLessEqual(len(ga.query(self.g, "?a -[link]-> ?b", limit=5)), 5)

    def test_multiple_paths_with_kinds(self):
        ps = ga.paths(self.g, "a1.md", "b3.md", 3)
        self.assertGreaterEqual(len(ps), 2)
        self.assertEqual(ps[0]["length"], min(p["length"] for p in ps))
        self.assertEqual(len({tuple(p["nodes"]) for p in ps}), len(ps), "同じ経路を重ねて返さない")
        for p in ps:
            self.assertEqual(p["nodes"][0], "a1.md")
            self.assertEqual(p["nodes"][-1], "b3.md")
            self.assertEqual(len(p["kinds"]), p["length"])
            self.assertTrue(all(p["kinds"]), "辺の種類が空の区間がない")
        self.assertEqual(ga.paths(self.g, "a1.md", "lonely.md"), [])        # つながらないなら空
        with self.assertRaises(ValueError):
            ga.paths(self.g, "a1.md", "zzz.md")

    def test_report_is_markdown_and_states_facts_only(self):
        md = ga.report(self.g)
        for h in ("# グラフ分析", "## つながりの多いノート（ハブ）", "## 異なる領域をつなぐノート", "## コミュニティ", "## 孤立", "## 循環", "## 関係の種類", "## Folgezettel の枝"):
            self.assertIn(h, md)
        self.assertIn("価値の大小を表すものではありません", md)                 # 指標を価値と混同しない
        self.assertIn("階層（親子）の不正な循環: 1 件", md)
        self.assertIn("循環1 ↔ 循環2", md)
        self.assertIn("(a1.md)", md)                                          # ノートへのリンク

    def test_read_only_and_cli(self):
        before = {p.name: p.read_bytes() for p in self.root.glob("*.md")}
        for cmd in (["hubs"], ["central"], ["bridges"], ["communities"], ["islands"], ["reach", "indexA.md"], ["cycles"], ["density"],
                    ["compare", "indexA.md", "indexB.md"], ["growth"], ["kinds"], ["query", "?a -[link]-> ?b"], ["paths", "a1.md", "b3.md"], ["report"]):
            self.assertEqual(ga.main([str(self.root)] + cmd), 0, cmd)
        self.assertEqual(ga.main([str(self.root), "reach", "nothing"]), 1)
        self.assertEqual(ga.main([str(self.root), "bogus"]), 2)
        self.assertEqual(before, {p.name: p.read_bytes() for p in self.root.glob("*.md")})


if __name__ == "__main__":
    unittest.main()
