#!/usr/bin/env python3
"""同期の解析の覚え（_fenced・_links_from・_code_spans）と、正規化パスの引き（_near）が、
覚えない版・従来の resolve() と同じ結果を返すことを、ランダムな入力で確かめる。"""
import os
import random
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import note_format_v2 as nf  # noqa: E402

PIECES = ["本文", "[題](a.md)", "[x](b.md#見出し)", "[外](https://e.com/x.md)", "`[c](c.md)`", "```", "~~~",
          "  ", "# 見出し", "ParentBranch:", "[壊](gone.md)", "文[y](../d.md)文", ""]


class SyncMemoTest(unittest.TestCase):
    def test_fenced_and_links_match_uncached(self):
        rnd = random.Random(7)
        for _ in range(400):
            lines = [rnd.choice(PIECES) for _ in range(rnd.randint(0, 12))]
            self.assertEqual(nf._fenced(lines), list(nf._fenced_uncached(lines)), lines)
            self.assertEqual(nf._links_from(lines), nf._links_from_uncached(lines), lines)
            # 2 回目（覚えた結果）も同じ
            self.assertEqual(nf._links_from(lines), nf._links_from_uncached(lines), lines)

    def test_code_spans_match(self):
        rnd = random.Random(3)
        for _ in range(300):
            ln = "".join(rnd.choice(PIECES) for _ in range(rnd.randint(0, 6)))
            spans = [m.span() for m in nf._INLINE_CODE_RE.finditer(ln)]
            self.assertEqual(list(nf._code_spans(ln)), spans, ln)

    def test_near_matches_resolve(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d).resolve()
            (root / "sub").mkdir()
            notes = [root / "a.md", root / "sub" / "b.md", root / "sub" / "c.md"]
            for p in notes:
                p.write_text("x", encoding="utf-8")
            notes_norm = {os.path.normpath(str(k)): k for k in notes}
            cands = ["a.md", "../a.md", "b.md", "./c.md", "../sub/c.md", "missing.md", "", "sub/b.md"]
            for base in notes + [root / "sub"]:
                for cand in cands:
                    self.assertEqual(nf._near(notes_norm, base, cand), (base.parent / cand).resolve(), (base, cand))


if __name__ == "__main__":
    unittest.main()
