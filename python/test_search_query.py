import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import search_query as sq

CASES = json.loads((Path(__file__).resolve().parent.parent / "test" / "search_query_cases.json").read_text(encoding="utf-8"))


class SearchQueryTests(unittest.TestCase):
    def test_parse_cases(self):
        for q, exp, note in CASES:
            got = [[g.pos, g.neg] for g in sq.parse(q)]
            self.assertEqual(got, exp, f"{q!r} {note}")

    def test_match(self):
        m = sq.match
        self.assertTrue(m("ハーブ -メモ", "ハーブの育て方"))
        self.assertFalse(m("ハーブ -メモ", "ハーブのメモ"))
        self.assertTrue(m("a | b", "xbx"))
        self.assertFalse(m("a | b", "xcx"))
        self.assertTrue(m("a b | c", "ab"))
        self.assertFalse(m("a b | c", "a"))
        self.assertTrue(m("a b | c", "c"))
        self.assertTrue(m('"育て 方"', "育て 方"))
        self.assertFalse(m('"育て 方"', "育ての方"))
        self.assertTrue(m("\\-foo", "a -foo b"))
        self.assertFalse(m("\\-foo", "foo"))
        self.assertTrue(m("-foo", "bar"))
        self.assertFalse(m("-foo", "foo"))
        self.assertTrue(m("INDEX", "Index"))
        self.assertTrue(m("ｉｎｄｅｘ", "index"))
        self.assertTrue(m("かたかな", "カタカナ"))
        self.assertTrue(m("", "なんでも"))
        self.assertTrue(m("a-b", "xa-bx"))
        self.assertFalse(m("a-b", "a b"))

    def test_terms(self):
        self.assertEqual(sq.terms("ハーブ -メモ | バジル ハーブ"), ["ハーブ", "バジル"])


if __name__ == "__main__":
    unittest.main()
