#!/usr/bin/env python3
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import capture_diag as cd
import capture_import as ci


class DiagTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(dir=str(Path.home() / "gnosis-work" / "test"))
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        note = "---\ntitle: A\ncapture: \ntopic: \"\"\n---\n\n# A\n\n本文\n"
        (self.root / "261019100000.md").write_text(note, encoding="utf-8")
        (self.root / "261019100000-2.md").write_text(note + "別版\n", encoding="utf-8")
        (self.root / "261019100000-3.md").write_text(note + "別版2\n", encoding="utf-8")
        (self.root / "other-2.md").write_text(note, encoding="utf-8")
        entry = dict(id="261019100000", created=1792371600000, topic="", text="本文", images=[], parent=None, contexts=[])
        (self.root / ".state").mkdir()
        ci.record(str(self.root), [("261019100000", "261019100000.md")], self._pack(entry))

    def _pack(self, entry):
        d = self.root.parent / (self.root.name + "-pack")
        d.mkdir(exist_ok=True)
        self.addCleanup(lambda: __import__("shutil").rmtree(d, ignore_errors=True))
        (d / "capture.json").write_text(json.dumps(dict(format="gnosis-capture", entries=[entry])), encoding="utf-8")
        return str(d)

    def test_duplicates_lists_versions_without_touching(self):
        before = sorted(p.name for p in self.root.glob("*.md"))
        d = cd.duplicates(self.root)
        self.assertEqual(d, [{"id": "261019100000", "original": "261019100000.md",
                              "versions": ["261019100000-2.md", "261019100000-3.md"]}])
        self.assertEqual(before, sorted(p.name for p in self.root.glob("*.md")))

    def test_strip_meta_dry_run_then_apply_is_idempotent(self):
        marked = '---\ntime: 2026-10-19 10:00:00\ncapture: gnosis\ncapture_id: 261019100000\ntopic: "gnosis"\n---\n\n# A\n\n本文\n'
        (self.root / "marked.md").write_text(marked, encoding="utf-8")
        only_topic = '---\ntime: 2026-10-19 10:00:00\ntopic: "手動"\n---\n\n# B\n'
        (self.root / "only_topic.md").write_text(only_topic, encoding="utf-8")
        topic_note = '---\ntime: 2026-10-19 10:00:00\ntopic: "gnosis"\ncapture_topic: "gnosis"\n---\n\n# gnosis\n'
        (self.root / "topic_note.md").write_text(topic_note, encoding="utf-8")
        plan = cd.strip_meta(self.root, False)
        self.assertEqual(sorted(p["file"] for p in plan if p["file"] in ("marked.md", "topic_note.md", "only_topic.md")),
                         ["marked.md", "topic_note.md"])  # topic: だけのノートには触らない
        self.assertEqual((self.root / "marked.md").read_text(encoding="utf-8"), marked)  # dry-run は書かない
        cd.strip_meta(self.root, True)
        self.assertEqual((self.root / "marked.md").read_text(encoding="utf-8"), '---\ntime: 2026-10-19 10:00:00\n---\n\n# A\n\n本文\n')
        self.assertEqual((self.root / "topic_note.md").read_text(encoding="utf-8"), '---\ntime: 2026-10-19 10:00:00\n---\n\n# gnosis\n')
        self.assertEqual((self.root / "only_topic.md").read_text(encoding="utf-8"), only_topic)
        self.assertEqual(cd.strip_meta(self.root, True), [])  # 2 回目は何もしない
        self.assertTrue((self.root / ".state" / "capture_strip.log").is_file())


if __name__ == "__main__":
    unittest.main()
