#!/usr/bin/env python3
import os, sys, tempfile, unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import orphans


class T(unittest.TestCase):
    def test_orphans(self):
        base = os.environ.get("TMPDIR") or None
        with tempfile.TemporaryDirectory(dir=base) as d:
            r = Path(d)
            (r / "index.md").write_text("# Index\n\n[a](a.md)\n", encoding="utf-8")
            (r / "a.md").write_text("# A\n\n[b](b.md)\n", encoding="utf-8")
            (r / "b.md").write_text("# B\n", encoding="utf-8")
            (r / "lone.md").write_text("# 孤立\n", encoding="utf-8")
            (r / "2026-10-19-月曜.md").write_text("# d\n\n[lone2](lone2.md)\n", encoding="utf-8")
            (r / "lone2.md").write_text("# 日記だけから\n", encoding="utf-8")
            (r / "261019110000.md").write_text('---\ntitle: 2026-10-19-MO\n---\n\n# 2026-10-19-MO\n\n## 今日のノート\n\n[lone](lone.md)\n', encoding="utf-8")
            (r / "lone.md").write_text('# 孤立\n\nBackLink:\n[日記](261019110000.md)\n', encoding="utf-8")
            got = sorted(p.name for p, _t, _c in orphans.find_orphans(r))
            self.assertEqual(got, ["lone.md", "lone2.md"])

    def test_topics_are_independent_of_creation_device(self):
        self.assertEqual(orphans._topic('---\ncapture: メモ\n---\n'), '')
        self.assertEqual(orphans._topic('---\ncapture: 仕事\n---\n'), '仕事')
        self.assertEqual(orphans._topic('---\ntopic: 仕事\n---\n'), '仕事')
        self.assertEqual(orphans._topic('---\ncapture: 仕事\ntopic: ""\n---\n'), '')
        self.assertEqual(orphans._topic('# 題\n\ncapture: 本文の一部'), '')
        self.assertEqual(orphans._topic('---\ntopic: "日本語: \\"引用\\""\n---\n'), '日本語: "引用"')


if __name__ == "__main__":
    unittest.main()
