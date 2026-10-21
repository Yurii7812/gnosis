#!/usr/bin/env python3
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import obsidian_search as os_  # noqa: E402

DOCS = [
    os_.Doc.make("a.md", "旅行の計画", "---\ntitle: 旅行の計画\ntags: [旅, 計画]\nstatus: 進行中\n---\n\n# 旅行の計画\n\n京都へ行く。新幹線で。\n\n## 持ち物\n- [ ] 着替え\n- [x] 切符を買う\n\nApple pie を食べる #食べ物"),
    os_.Doc.make("diary/b.md", "2026-10-21-TU", "# 2026-10-21-TU\n\n朝に京都の本を読んだ。\nりんご ジャム を作った。\nりんごとジャムは別の行。\n"),
    os_.Doc.make("c.md", "ジャムの作り方", "# ジャムの作り方\n\n砂糖と りんご。\n\n小麦粉\n砂糖\n"),
]


def rels(q, **kw):
    return [r["rel"] for r in os_.search(DOCS, q, **kw)["results"]]


class ObsidianSearchTest(unittest.TestCase):
    def test_words_are_and_anywhere_in_note(self):
        self.assertEqual(rels("京都 本"), ["diary/b.md"])
        self.assertEqual(rels("京都"), ["a.md", "diary/b.md"])

    def test_phrase_or_not_group(self):
        self.assertEqual(rels('"りんご ジャム"'), ["diary/b.md"])
        self.assertEqual(rels("新幹線 OR 小麦粉"), ["a.md", "c.md"])
        self.assertEqual(rels("りんご -京都"), ["c.md"])
        self.assertEqual(rels("(新幹線 OR 小麦粉) 砂糖"), ["c.md"])

    def test_operators(self):
        self.assertEqual(rels("file:旅行"), ["a.md"])                 # 題にも当たる（Gnosis のファイル名は時刻なので）
        self.assertEqual(rels("path:diary/"), ["diary/b.md"])
        self.assertEqual(rels("content:ジャム"), ["diary/b.md", "c.md"])
        self.assertEqual(rels("line:(小麦粉 砂糖)"), [])                # 別の行
        self.assertEqual(rels("block:(小麦粉 砂糖)"), ["c.md"])         # 同じ段落
        self.assertEqual(rels("line:(りんご ジャム)"), ["diary/b.md"])
        self.assertEqual(rels("section:(着替え 切符)"), ["a.md"])
        self.assertEqual(rels("section:(京都 着替え)"), [])             # 見出しが違う
        self.assertEqual(rels("task-todo:着替え"), ["a.md"])
        self.assertEqual(rels("task-done:着替え"), [])
        self.assertEqual(rels("task:切符"), ["a.md"])
        self.assertEqual(rels("tag:#食べ物"), ["a.md"])
        self.assertEqual(rels("tag:旅"), ["a.md"])                      # front matter の tags
        self.assertEqual(rels("[status:進行]"), ["a.md"])
        self.assertEqual(rels("[status]"), ["a.md"])
        self.assertEqual(rels("/\\d{4}-\\d\\d-\\d\\d/"), ["diary/b.md"])

    def test_case(self):
        self.assertEqual(rels("apple"), ["a.md"])
        self.assertEqual(rels("apple", match_case=True), [])
        self.assertEqual(rels("match-case:apple"), [])
        self.assertEqual(rels("match-case:Apple"), ["a.md"])
        self.assertEqual(rels("ignore-case:APPLE", match_case=True), ["a.md"])

    def test_hits_have_lines_and_ranges(self):
        r = os_.search(DOCS, "京都 本")["results"][0]
        ln = r["lines"][0]
        self.assertEqual(ln["line"], 3)
        self.assertEqual([ln["text"][a:b] for a, b in ln["ranges"]], ["京都", "本"])
        ex = os_.search(DOCS, "京都 -本")["explain"]
        self.assertIn("含まない", ex)

    def test_partial_and_bad_queries(self):
        self.assertEqual(rels(""), [])
        self.assertEqual(rels("file:"), [])
        self.assertEqual(rels("(京都"), ["a.md", "diary/b.md"])       # 閉じていないかっこ
        with self.assertRaises(os_.QueryError):
            os_.search(DOCS, "/[/")


if __name__ == "__main__":
    unittest.main()
