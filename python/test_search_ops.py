"""gs（note_search）と s（mandala_search / mandala_cache）が、検索の書き方（AND・NOT・OR・句・\\ による文字）どおりに探す。"""
import os
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import mandala_search as ms
import note_search as ns


def note(title, body=""):
    return f"---\ntime: 2026-01-01 00:00:00\ntitle: {title}\n---\n\n# {title}\n\n{body}\n"


class SearchOps(unittest.TestCase):
    def setUp(self):
        self.d = tempfile.TemporaryDirectory(dir=os.environ.get("TMPDIR"))
        r = Path(self.d.name)
        (r / "herb.md").write_text(note("ハーブ", "育て方のメモ"), encoding="utf-8")
        (r / "basil.md").write_text(note("バジル", "ハーブの一種。料理に使う"), encoding="utf-8")
        (r / "memo.md").write_text(note("メモ", "ハーブについて書く -foo と a|b と 100% のこと"), encoding="utf-8")
        (r / "cook.md").write_text(note("料理", "カレー"), encoding="utf-8")
        self.r = r

    def tearDown(self):
        self.d.cleanup()

    def gs(self, q):
        return sorted(Path(row[3]).name for row in ns.search_rows(str(self.r), q))

    def items(self):
        return [(p.name, ns.title_of(p.read_text(encoding="utf-8"), str(p))[0], (lambda p=p: p.read_text(encoding="utf-8"))) for p in sorted(self.r.glob("*.md"))]

    def s(self, q):
        return sorted(ms.rank(self.items(), q))

    def test_and_not_or(self):
        for f in (self.gs, self.s):
            self.assertEqual(f("ハーブ メモ"), ["herb.md", "memo.md"])             # AND（題か本文に両方）
            self.assertNotIn("memo.md", f("ハーブ -メモ"))                         # NOT
            self.assertIn("basil.md", f("ハーブ -メモ"))
            self.assertEqual(f("カレー | バジル"), ["basil.md", "cook.md"])        # OR
            self.assertEqual(f("バジル 料理 | カレー"), ["basil.md", "cook.md"])   # AND は OR より強い
            self.assertEqual(f("-ハーブ -カレー"), [])                             # 除外だけ（全部に ハーブ か カレー がある…ではなく）
        self.assertIn("cook.md", self.gs("-メモ -バジル"))

    def test_literal_operators(self):
        for f in (self.gs, self.s):
            self.assertEqual(f("\\-foo"), ["memo.md"])        # -foo を文字として
            self.assertEqual(f('"-foo"'), ["memo.md"])
            self.assertEqual(f("a\\|b"), ["memo.md"])         # | を文字として
            self.assertEqual(f('"a|b"'), ["memo.md"])
            self.assertEqual(f("100%"), ["memo.md"])         # ふつうの記号
            self.assertEqual(f('"育て方"'), ["herb.md"])

    def test_phrase_and_normalization(self):
        for f in (self.gs, self.s):
            self.assertIn("herb.md", f("ハーブ"))
            self.assertIn("herb.md", f("はーぶ"))             # カタカナ ↔ ひらがな
            self.assertEqual(f("ＺＺＺ"), [])               # 無いものは無い
        open(self.r / "en.md", "w", encoding="utf-8").write(note("Index", "Hello"))
        self.assertIn("en.md", self.gs("ｉｎｄｅｘ"))
        self.assertIn("en.md", self.s("INDEX"))

    def test_empty_query(self):
        self.assertEqual(len(self.gs("")), 4)                  # gs は空なら全件
        self.assertEqual(self.s(""), [])                       # s は空なら何も探さない（従来どおり）


if __name__ == "__main__":
    unittest.main()
