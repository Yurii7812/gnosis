#!/usr/bin/env python3
import contextlib
import hashlib
import io
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import hypotheses as hy

NOTE = """---
time: 2026-01-01 00:00:00
title: 睡眠の研究
---

# 睡眠の研究

仮説: 睡眠は記憶の定着に効く
状態: 検証中
+ 証拠: 学習後の睡眠で成績が上がった [論文](paper.md)
+ 証拠: 別の実験でも同じ結果 [追試](paper2.md#r)
- 反証: 昼寝だけでは差が出なかった [実験](nap.md)
結論: 当面は支持する
履歴: 2026-10-01 検証中 / 2026-10-15 支持

- 仮説: 昼寝は逆効果
- 反証: [論文](paper.md)

```
仮説: コードの中は読まない
```

仮説: 空の仮説
"""


class HypothesesTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(dir=str(Path.home() / "gnosis-work" / "test"))
        self.addCleanup(self.tmp.cleanup)
        r = self.root = Path(self.tmp.name)
        (r / "sleep.md").write_text(NOTE, encoding="utf-8")
        (r / "other.md").write_text("---\ntitle: 反対派\n---\n\n# 反対派\n\n仮説: 睡眠より運動が効く\n+ 証拠: [論文](paper.md)\n- 反証: 追試で消えた [追試](paper2.md)\n- 反証: 別の研究 [x](x.md)\n", encoding="utf-8")
        (r / "none.md").write_text("# なし\n\n普通のノート\n", encoding="utf-8")
        self.before = {p.name: hashlib.md5(p.read_bytes()).hexdigest() for p in r.glob("*.md")}

    def same(self):
        self.assertEqual(self.before, {p.name: hashlib.md5(p.read_bytes()).hexdigest() for p in self.root.glob("*.md")})

    def test_parse_blocks(self):
        hs = hy.parse_text(NOTE, "sleep.md")
        self.assertEqual([h["claim"] for h in hs], ["睡眠は記憶の定着に効く", "昼寝は逆効果", "空の仮説"])      # コードの中は読まない
        h = hs[0]
        self.assertEqual((h["status"], h["conclusion"]), ("検証中", "当面は支持する"))
        self.assertEqual([e["links"][0]["target"] for e in h["evidence"]], ["paper.md", "paper2.md"])         # #アンカーは外した先
        self.assertEqual(len(h["counter"]), 1)
        self.assertEqual(h["history"], [{"date": "2026-10-01", "status": "検証中"}, {"date": "2026-10-15", "status": "支持"}])
        self.assertEqual(h["line"], 8)
        self.assertEqual(len(hs[1]["counter"]), 1)                                                          # 箇条書きの仮説・反証も読める
        self.assertEqual((hs[2]["evidence"], hs[2]["counter"], hs[2]["status"]), ([], [], ""))

    def test_block_ends_at_blank_line(self):
        hs = hy.parse_text("仮説: A\n+ 証拠: 1\n\n+ 証拠: 空行のあと(どの仮説にも属さない)\n", "x.md")
        self.assertEqual(len(hs[0]["evidence"]), 1)

    def test_suggest_never_decides(self):
        mk = lambda p, c: {"evidence": [1] * p, "counter": [1] * c}
        for p, c, want in ((0, 0, "検証中"), (3, 0, "支持"), (0, 2, "棄却"), (4, 2, "支持"), (2, 4, "棄却"), (3, 2, "保留"), (1, 1, "保留")):
            self.assertEqual(hy.suggest(mk(p, c))["status"], want, (p, c))
        self.assertIn("判断は自分で", hy.suggest(mk(1, 0))["note_text"])

    def test_collect_and_list(self):
        r = hy.list_hyp(self.root)
        self.assertEqual(r["count"], 4)
        self.assertEqual(r["by_status"], {"検証中": 1, "未設定": 3})
        first = next(h for h in r["hypotheses"] if h["claim"] == "睡眠は記憶の定着に効く")
        self.assertEqual((first["pro"], first["con"], first["id"], first["note_title"]), (2, 1, "sleep.md#1", "睡眠の研究"))
        self.assertEqual(hy.list_hyp(self.root, "検証中")["count"], 1)
        self.assertEqual(hy.list_hyp(self.root, "未設定")["count"], 3)
        self.assertEqual(hy.list_hyp(self.root, "棄却")["count"], 0)
        self.same()

    def test_show(self):
        self.assertEqual(len(hy.show(self.root, "sleep.md")["hypotheses"]), 3)
        self.assertEqual(hy.show(self.root, "睡眠の研究", 2)["hypotheses"][0]["claim"], "昼寝は逆効果")
        with self.assertRaises(ValueError):
            hy.show(self.root, "none.md")
        with self.assertRaises(ValueError):
            hy.show(self.root, "sleep.md", 9)

    def test_debate_compares_and_finds_clashes(self):
        d = hy.debate(self.root, "睡眠は記憶", "運動が効く")
        self.assertEqual((d["A"]["pro"], d["A"]["con"], d["B"]["pro"], d["B"]["con"]), (2, 1, 1, 2))
        self.assertEqual(d["lead"], "A")                                                                      # 差(+1)と(-1)
        self.assertEqual(d["shared_sources"], ["paper.md", "paper2.md"])
        roles = {c["target"]: (c["A"], c["B"]) for c in d["clashes"]}
        self.assertEqual(roles, {"paper2.md": ("証拠", "反証")})                    # 同じ出典を逆の立場で使っているものだけ(paper.md は両方が証拠なので食い違いではない)
        self.assertIn("内容の正しさは判断していません", d["note_text"])
        self.same()

    def test_debate_errors(self):
        with self.assertRaises(ValueError) as cm:
            hy.debate(self.root, "睡眠は記憶", "睡眠は記憶")                          # 同じ仮説どうし
        self.assertIn("別々", str(cm.exception))
        with self.assertRaises(ValueError) as cm:
            hy.debate(self.root, "存在しない主張", "運動が効く")
        self.assertIn("見つかりません", str(cm.exception))
        with self.assertRaises(ValueError) as cm:
            hy.debate(self.root, "睡眠", "運動が効く")                                # 「睡眠」は 2 件に当てはまる
        self.assertIn("ノート#番号", str(cm.exception))
        d = hy.debate(self.root, "sleep.md#2", "other.md#1")                         # ノート#番号 なら曖昧さがない
        self.assertEqual(d["A"]["claim"], "昼寝は逆効果")

    def test_markdown_and_cli(self):
        def run(*a):
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                rc = hy.main([str(self.root), *a])
            return rc, buf.getvalue()
        self.assertIn("# 仮説 4 件", run("list", "--md")[1])
        self.assertIn("目安: 支持", run("list", "--md")[1])
        self.assertIn("## 証拠", run("show", "sleep.md", "1", "--md")[1])
        self.assertIn("| 証拠 | 2 | 1 |", run("debate", "睡眠は記憶", "運動が効く", "--md")[1])
        self.assertEqual(run("list", "--status", "検証中")[0], 0)
        self.assertEqual(run("show", "none.md")[0], 1)
        self.assertEqual(run("bogus")[0], 2)
        self.same()


if __name__ == "__main__":
    unittest.main()
