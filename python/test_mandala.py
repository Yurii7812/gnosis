#!/usr/bin/env python3
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import mandala as md


class MandalaTest(unittest.TestCase):
    def test_new_has_81_cells_and_mirrors(self):
        text = md.new_text("健康", ["運動", "食事", "睡眠", "心", "お金", "学び", "人", "遊び"])
        self.assertTrue(md.is_mandala(text))
        g = md.parse(text)
        self.assertEqual(len(g), 9)
        self.assertTrue(all(len(r) == 9 for r in g))
        self.assertEqual(g[4][4], "健康")
        for i, name in enumerate(["運動", "食事", "睡眠", "心", "お金", "学び", "人", "遊び"]):
            self.assertEqual(g[md.RING[i][0]][md.RING[i][1]], name)
            self.assertEqual(g[md.BLOCK_CENTER[i][0]][md.BLOCK_CENTER[i][1]], name)
        # 8 つの副題と周囲のブロックの中心は、重ならず 81 マスの中で別々
        cells = [md.THEME] + md.RING + md.BLOCK_CENTER
        self.assertEqual(len(set(cells)), 17)
        # 周囲のブロックの中心は、各 3×3 ブロックの中心(行・列とも 1,4,7)
        for r, c in md.BLOCK_CENTER:
            self.assertIn(r, (1, 4, 7)); self.assertIn(c, (1, 4, 7))
        self.assertNotIn((4, 4), md.BLOCK_CENTER)

    def test_markdown_table_is_plain(self):
        text = md.new_text("主題", ["a"])
        body = text.split("---\n", 2)[2]
        rows = [ln for ln in body.split("\n") if ln.startswith("|")]
        self.assertEqual(len(rows), 11)             # 列名 + 区切り + 9 行
        self.assertTrue(all(r.count("|") == 10 for r in rows))   # 9 列

    def test_sync_fills_and_reports_conflicts_without_overwriting(self):
        g = [["" for _ in range(9)] for _ in range(9)]
        g[4][4] = "主題"
        g[3][3] = "A"                                # 中心ブロックの副題だけ
        g[1][4] = "B(別)"; g[3][4] = "B"             # 周囲側と中心側が食い違う
        g[7][7] = "E"                                # 周囲側だけ（副題 5）
        text = "---\ntitle: t\nmandala: true\n---\n\n# t\n\nまえがき\n\n" + "\n".join(md.render_table(g)) + "\n\nあとがき\n"
        new, rep = md.sync(text)
        n = md.parse(new)
        self.assertEqual(n[1][1], "A")               # 中心ブロック → 周囲
        self.assertEqual(n[4][4], "主題")
        self.assertEqual(n[5][5], "E")               # 周囲 → 中心ブロック
        self.assertEqual((n[1][4], n[3][4]), ("B(別)", "B"))   # 食い違いはどちらも変えない
        self.assertEqual(len(rep["conflicts"]), 1)
        self.assertEqual(rep["conflicts"][0]["ring_value"], "B")
        self.assertIn("まえがき", new); self.assertIn("あとがき", new)
        # 2 回目は何も変わらない
        again, rep2 = md.sync(new)
        self.assertEqual(again, new); self.assertEqual(rep2["filled"], [])

    def test_html_grid_and_links(self):
        g = [["" for _ in range(9)] for _ in range(9)]
        g[4][4] = "主題"; g[3][3] = "[詳細](note.md)"; g[0][0] = "[別の曼荼羅](other.md)"; g[8][8] = "<b>x</b>"
        h = md.to_html(g)
        self.assertEqual(h.count("<tr>"), 9)
        self.assertEqual(h.count("<td"), 81)
        self.assertIn('<a href="note.html">詳細</a>', h)
        self.assertIn('<a href="other.html">別の曼荼羅</a>', h)
        self.assertIn("&lt;b&gt;x&lt;/b&gt;", h)
        self.assertEqual(h.count('class="m theme'), 1)

    def test_cli_new_does_not_overwrite(self):
        with tempfile.TemporaryDirectory(dir=str(Path.home() / "gnosis-work" / "test")) as d:
            p = Path(d) / "m.md"
            self.assertEqual(md.main(["new", str(p), "主題", "a", "b"]), 0)
            before = p.read_text(encoding="utf-8")
            self.assertEqual(md.main(["new", str(p), "別", "z"]), 1)
            self.assertEqual(p.read_text(encoding="utf-8"), before)
            self.assertEqual(md.main(["sync", str(p)]), 0)
            self.assertEqual(p.read_text(encoding="utf-8"), before)    # 揃っていれば書き換えない

    def test_link_cell_creates_real_note_and_keeps_mirror_in_sync(self):
        with tempfile.TemporaryDirectory(dir=str(Path.home() / "gnosis-work" / "test")) as d:
            p = Path(d) / "m.md"
            p.write_text(md.new_text("健康", ["運動", "食事"]), encoding="utf-8")
            r = md.link_cell(p, 3, 3, "note")                # 中心ブロックの副題「運動」
            self.assertTrue(r["ok"])
            made = Path(d) / r["file"]
            self.assertIn("# 運動", made.read_text(encoding="utf-8"))   # 実際の Markdown ノート
            g = md.parse(p.read_text(encoding="utf-8"))
            self.assertEqual(g[3][3], f"[運動]({r['file']})")
            self.assertEqual(g[1][1], g[3][3])               # 周囲側の同じ副題も同じリンク
            new, rep = md.sync(p.read_text(encoding="utf-8"))
            self.assertEqual(rep["conflicts"], [])           # 食い違いにならない
            self.assertFalse(md.link_cell(p, 3, 3)["ok"])    # もうリンクがある
            self.assertFalse(md.link_cell(p, 0, 0)["ok"])    # 空のマス
            r2 = md.link_cell(p, 3, 4, "mandala")            # 別の曼荼羅へ
            sub = (Path(d) / r2["file"]).read_text(encoding="utf-8")
            self.assertTrue(md.is_mandala(sub))
            self.assertEqual(md.parse(sub)[4][4], "食事")
            self.assertEqual(len(list(Path(d).glob("*.md"))), 3)
            # 行・桁からマスを引ける（全角文字を含む行でもバイト桁で正しく）
            text = p.read_text(encoding="utf-8")
            lines = text.split("\n")
            header = next(i for i, x in enumerate(lines) if x.startswith("| 1 | 2 |"))
            for (r, c) in ((3, 4), (5, 5), (8, 8), (0, 0)):
                ln = header + 2 + r + 1                      # 1 から数えた行
                row = lines[ln - 1]
                pipes = [i for i, ch in enumerate(row) if ch == "|"]
                start = len(row[:pipes[c] + 1].encode("utf-8"))      # c 番目の縦線の直後（バイト）
                self.assertEqual(md.locate(text, ln, start + 1), (r, c), (r, c, row))
                self.assertEqual(md.locate(text, ln, start + 2), (r, c))    # マスの中ほど
            self.assertIsNone(md.locate(p.read_text(encoding="utf-8"), 1, 1))

    def test_several_pages_same_theme(self):
        # 副題が 8 つを超えたら、同じノートに 2 枚目の 9×9 を足す（どの表も同じ主題）
        text = md.new_text("健康", ["運動", "食事"]) + "\nあとがき。\n"
        g1 = md.parse(text)
        g2 = [["" for _ in range(9)] for _ in range(9)]
        g2[3][3] = "睡眠"
        two = md.replace_tables(text, [g1, g2])
        self.assertTrue(two.endswith("あとがき。\n"))               # 表の外の本文はそのまま
        self.assertEqual(len(md.parse_all(two)), 2)
        self.assertEqual(md.parse(two)[3][3], "運動")                 # 1 枚目だけを読む古い読み方も同じ
        new, rep = md.sync(two)
        p2 = md.parse_all(new)[1]
        self.assertEqual(p2[4][4], "健康")                            # 2 枚目の主題は 1 枚目から
        self.assertEqual(p2[1][1], "睡眠")                            # 2 枚目の副題も 2 か所にそろう
        self.assertTrue(all(x["page"] == 1 for x in rep["filled"]))
        self.assertEqual(md.replace_tables(new, md.parse_all(new)), new)   # 読んで書き直しても変わらない
        # 減らすと表も消える
        self.assertEqual(len(md.parse_all(md.replace_tables(new, md.parse_all(new)[:1]))), 1)
        # 行・桁から何枚目のどのマスかを引ける・2 枚目のマスからノートを作れる
        lines = new.split("\n")
        blk = md.table_blocks(lines)[1]
        row = lines[blk[0] + 2 + 3]
        pipes = [i for i, ch in enumerate(row) if ch == "|"]
        self.assertEqual(md.locate_page(new, blk[0] + 2 + 3 + 1, len(row[:pipes[3] + 1].encode()) + 2), (1, 3, 3))
        with tempfile.TemporaryDirectory(dir=str(Path.home() / "gnosis-work" / "test")) as d:
            p = Path(d) / "m.md"
            p.write_text(new, encoding="utf-8")
            r = md.link_cell(p, 3, 3, "note", 1)
            self.assertTrue(r["ok"], r)
            after = md.parse_all(p.read_text(encoding="utf-8"))
            self.assertEqual(after[1][3][3], f"[睡眠]({r['file']})")
            self.assertEqual(after[1][1][1], after[1][3][3])
            self.assertEqual(after[0][3][3], "運動")                  # 1 枚目は触らない
            self.assertIn("table class=\"mandala\"", md.to_html(after[1]))

    def test_too_many_subs(self):
        with self.assertRaises(ValueError):
            md.new_text("x", list("123456789"))


if __name__ == "__main__":
    unittest.main()
