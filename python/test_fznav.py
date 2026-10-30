#!/usr/bin/env python3
"""Folgezettel ビュー（fznav.py）の試験。一時フォルダの vault だけを使う。"""
import os
import sys
import tempfile
import time
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import fznav as fz  # noqa: E402
import mandala_cache as mc  # noqa: E402


def mk(title, fzid="", group=False, bg=(), grp=(), links=()):
    s = f"---\ntime: 2026-01-01 00:00:00\ntitle: {title}\n" + ("attribute: group\n" if group else "") + (f'folgezettel: "{fzid}"\n' if fzid else "") + f"---\n\n# {title}\n\n"
    if bg:
        s += "BranchGroup:\n" + "".join(f"[{t}]({f})\n" for t, f in bg) + "\n"
    if grp:
        s += "Group:\n" + "".join(f"[{t}]({f})\n" for t, f in grp) + "\n"
    return s + "".join(f"[{t}]({f})\n" for t, f in links)


class T(unittest.TestCase):
    def setUp(self):
        base = os.environ.get("TMPDIR") or str(Path.home() / "gnosis-work" / "test")
        os.makedirs(base, exist_ok=True)
        self.tmp = tempfile.TemporaryDirectory(dir=base)
        self.r = r = Path(self.tmp.name)
        w = lambda name, text: (r / name).write_text(text)
        w("index.md", mk("Index"))
        # 番号つきのノート（欠番: 1a1 と 3 が無い）。1 / 1a / 1a2 は BranchGroup を持つ（グループも同じ番号）
        w("n1.md", mk("認識", "1", bg=[("認識G", "g1.md")]))
        w("g1.md", mk("認識G", "1", group=True, links=[("知覚", "n1a.md"), ("共有の項目", "n9.md")]))
        w("n1a.md", mk("知覚", "1a", bg=[("知覚G", "g1a.md")], grp=[("言語G", "gl.md")]))
        w("g1a.md", mk("知覚G", "1a", group=True))
        w("n1a1a.md", mk("言語", "1a1a", grp=[("言語G", "gl.md")]))
        w("n1a1b.md", mk("意味", "1a1b", links=[("記憶", "n1a2.md")]))
        w("n1a2.md", mk("記憶", "1a2", bg=[("記憶G", "g1a2.md")]))
        w("g1a2.md", mk("記憶G", "1a2", group=True))
        w("n1b.md", mk("意識", "1b"))
        w("n1z.md", mk("1z", "1z"))
        w("n1aa.md", mk("1aa", "1aa"))
        w("n2.md", mk("二", "2"))
        w("n10.md", mk("十", "10"))
        w("n3a.md", mk("三a", "3a"))
        w("n9.md", mk("遠い", "9", bg=[("遠いG", "g9.md")]))
        w("g9.md", mk("遠いG", "9", group=True))
        w("n_free.md", mk("番号なし"))
        w("gl.md", mk("言語G", group=True, links=[("言語", "n1a1a.md"), ("知覚", "n1a.md")]))
        # 番号が近いだけ（1a1c）で、周辺のノートが 1 つも載っていないグループ（番号は共有しない普通のグループ）
        w("n1a1c.md", mk("無関係の隣", "1a1c", grp=[("孤立G", "gx.md")]))
        w("gx.md", mk("孤立G", group=True, links=[("無関係の隣", "n1a1c.md"), ("番号なし", "n_free.md")]))
        mc.refresh(r)

    def tearDown(self):
        self.tmp.cleanup()

    def rows(self, numw=8):
        return fz.rows(self.r, numw)["rows"]

    def test_natural_order_and_group_first(self):
        ids = [(x[0], x[3]) for x in self.rows()]
        self.assertEqual([i for i, _ in ids if _ == "n"],
                         ["1", "1a", "1a1a", "1a1b", "1a1c", "1a2", "1b", "1z", "1aa", "2", "3a", "9", "10"])
        self.assertEqual(ids[:5], [("1", "g"), ("1", "n"), ("1a", "g"), ("1a", "n"), ("1a1a", "n")])
        # 番号なしのノートは行にならない・架空のグループも作らない
        self.assertNotIn("n_free.md", [x[1] for x in self.rows()])
        self.assertEqual(sum(1 for x in self.rows() if x[3] == "g"), 4)   # g1 g1a g1a2 g9
        self.assertNotIn("gl.md", [x[1] for x in self.rows()])            # 番号を共有しないグループは行にしない

    def test_hierarchy(self):
        rs = self.rows()
        at = {(x[0], x[3]): i for i, x in enumerate(rs)}
        n1a1a = at[("1a1a", "n")]
        # 1a1 が欠番でも、1a の子孫として 1a の次に来る
        self.assertEqual(rs[n1a1a][5], at[("1a", "g")])            # 上 = 1a のブロックの先頭
        self.assertEqual(rs[at[("1a", "n")]][8], n1a1a)            # 下 = 最初の子孫
        self.assertEqual(rs[at[("1a", "n")]][6], at[("1a", "n")])  # ブロックの終わり
        self.assertEqual(rs[at[("1a", "g")]][6], at[("1a", "n")])
        # 1a の部分木の終わり = 1b の Note の行（1b にグループは無い）
        self.assertEqual(rs[at[("1a", "n")]][7], at[("1b", "n")])
        # 1b / 1z / 1aa は 1a の子孫ではない（文字列の前方一致で親子にしない）
        self.assertEqual(rs[at[("1aa", "n")]][5], at[("1", "g")])
        self.assertEqual(rs[at[("2", "n")]][5], -1)
        self.assertEqual(rs[at[("2", "n")]][8], -1)
        # 3a は 3 が無くても最上位
        self.assertEqual(rs[at[("3a", "n")]][5], -1)

    def test_abbreviate(self):
        self.assertEqual(fz.abbreviate("1a2b"), "1a2b")
        self.assertEqual(fz.abbreviate("12345678"), "12345678")
        self.assertEqual(fz.abbreviate("1a2b3c4d5e", 8), "~b3c4d5e")
        for w in range(3, 12):
            self.assertLessEqual(len(fz.abbreviate("1a2b3c4d5e6f7g8h", w)), w)
        self.assertEqual(fz.abbreviate("12abcdefghijkl", 5), "~ijkl")   # 1 つの区切りも入らないときは末尾の文字

    def test_deep_id_row_keeps_real_id(self):
        (self.r / "deep.md").write_text(mk("深い", "1a1b2c3d4e5"))
        mc.refresh(self.r, force=True)
        row = next(x for x in self.rows() if x[1] == "deep.md")
        self.assertEqual(row[0], "1a1b2c3d4e5")
        self.assertTrue(row[4].startswith("~") and len(row[4]) <= 8)

    def test_upper_chain_and_content_related_groups(self):
        # 祖先のグループ表示だけは Folgezettel 階層を維持する。
        u = fz.upper(self.r, "n1a1a.md")
        self.assertEqual([c["id"] for c in u["chain"]], ["1", "1a"])
        self.assertEqual([c["path"] for c in u["chain"]], ["g1.md", "g1a.md"])
        # 意味のある本文を追加。番号の離れたノートでも内容が近ければ
        # それを含むグループが関連グループに現れる。
        with (self.r / "n1a1a.md").open("a") as w:
            w.write("\\n意味生成 言語文法 言語構造 理解の過程\\n".replace("\\\\n", "\\n"))
        (self.r / "distant.md").write_text(
            mk("言語文法と意味生成", "900", grp=[("研究グループ", "semantic.md")])
            + "言語構造から意味生成を考える\\n")
        (self.r / "semantic.md").write_text(
            mk("研究グループ", group=True, links=[("研究内容", "distant.md")]))
        mc.refresh(self.r, force=True)
        groups = [d["path"] for d in fz.upper(self.r, "n1a1a.md")["related"]]
        self.assertIn("semantic.md", groups)
        self.assertNotIn("g1.md", groups)
        self.assertNotIn("g1a.md", groups)
        self.assertNotIn("g9.md", groups)

    def test_related_ignores_number_and_link_without_content(self):
        # 機械的な番号・リンクだけでは関連グループにしない。
        for name in ["n2.md", "n1b.md", "n1a1b.md"]:
            groups = fz.upper(self.r, name)["related"]
            self.assertEqual(groups, [], (name, groups))

    def test_related_deterministic(self):
        u1 = fz.upper(self.r, "n1a1b.md")
        u2 = fz.upper(self.r, "n1a1b.md")
        self.assertEqual(u1, u2)
        scores = [r["score"] for r in u1["related"]]
        self.assertEqual(scores, sorted(scores, reverse=True))

    def test_no_fz_note_and_missing(self):
        u = fz.upper(self.r, "n_free.md")
        self.assertTrue(u["ok"])
        self.assertEqual(u["chain"], [])
        self.assertFalse(fz.upper(self.r, "nothing.md")["ok"])

    def test_many_notes(self):
        for i in range(1, 3001):
            (self.r / f"bulk{i}.md").write_text(mk(f"B{i}", f"100{i % 7}a{i}"))
        mc.refresh(self.r, force=True)
        t = time.time()
        rs = self.rows()
        self.assertGreater(len(rs), 3000)
        self.assertLess(time.time() - t, 5)
        keys = [fz.natural_key(x[0]) for x in rs]
        self.assertEqual(keys, sorted(keys))

    def test_outline(self):
        lines = ["---", "title: x", "---", "# 題", "本文", "## 節", "```", "# コード", "```", "### 小節 ###", "#タグ", "## "]
        self.assertEqual([(i["level"], i["text"], i["lnum"]) for i in fz.outline_items(lines)],
                         [(1, "題", 4), (2, "節", 6), (3, "小節", 10)])


if __name__ == "__main__":
    unittest.main()
