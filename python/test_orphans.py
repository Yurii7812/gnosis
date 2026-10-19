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
            got = sorted(p.name for p, _ in orphans.find_orphans(r))
            self.assertEqual(got, ["lone.md", "lone2.md"])


if __name__ == "__main__":
    unittest.main()
