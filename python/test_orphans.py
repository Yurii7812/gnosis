#!/usr/bin/env python3
import os, sys, tempfile, unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import orphans


class T(unittest.TestCase):
    def test_orphans(self):
        """Folgezettel ID が無く、かつ親（Branch）も無いノートが未所属。Index から・日記から Branch でたどれるものには番号が付く（付く予定も含む）。
        親があるノートは、親に番号が無くても出さない。BackLink・Context だけでは所属にならない。Index にも日記にもなく親もないノートは、番号が外れて未所属になる。"""
        base = os.environ.get("TMPDIR") or None
        with tempfile.TemporaryDirectory(dir=base) as d:
            r = Path(d)
            (r / "index.md").write_text("# Index\n\n[a](a.md)\n", encoding="utf-8")
            (r / "a.md").write_text("# A\n\nChildBranch:\n[b](b.md)\n", encoding="utf-8")
            (r / "b.md").write_text("# B\n\nParentBranch:\n[a](a.md)\n", encoding="utf-8")
            (r / "lone.md").write_text("# 孤立\n\n[a](a.md)\n", encoding="utf-8")
            (r / "old.md").write_text('---\ntitle: 前に番号\nfolgezettel: "9"\n---\n\n# 前に番号\n', encoding="utf-8")
            (r / "261019110000.md").write_text('---\ntitle: 2026-10-19-MO\n---\n\n# 2026-10-19-MO\n\n## 今日のノート\n\n[lone](lone.md)\n\nChildBranch:\n[伸びた](grow.md)\n', encoding="utf-8")
            (r / "grow.md").write_text('# 伸びた\n\nParentBranch:\n[日記](261019110000.md)\n', encoding="utf-8")
            (r / "g.md").write_text('---\ntitle: G\nattribute: group\n---\n\n# G\n', encoding="utf-8")
            (r / "12a.md").write_text('---\ntitle: 12a\n---\n\n# 12a\n', encoding="utf-8")
            # 番号の無い lone を親にしている子は、親をたどれるので出さない
            (r / "kid.md").write_text("# 子\n\nParentBranch:\n[孤立](lone.md)\n", encoding="utf-8")
            got = sorted(p.name for p, _t, _c in orphans.find_orphans(r))
            self.assertEqual(got, ["lone.md", "old.md"])

    def test_topics_are_independent_of_creation_device(self):
        self.assertEqual(orphans._topic('---\ncapture: メモ\n---\n'), '')
        self.assertEqual(orphans._topic('---\ncapture: 仕事\n---\n'), '仕事')
        self.assertEqual(orphans._topic('---\ntopic: 仕事\n---\n'), '仕事')
        self.assertEqual(orphans._topic('---\ncapture: 仕事\ntopic: ""\n---\n'), '')
        self.assertEqual(orphans._topic('# 題\n\ncapture: 本文の一部'), '')
        self.assertEqual(orphans._topic('---\ntopic: "日本語: \\"引用\\""\n---\n'), '日本語: "引用"')


if __name__ == "__main__":
    unittest.main()
