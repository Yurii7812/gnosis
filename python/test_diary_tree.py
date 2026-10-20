"""日記と時系列記録の木（グループ → 普通のノート＋ParentBranch:）の移行の回帰網。"""
import tempfile
import unittest
from pathlib import Path

import branch_ops as bo
import diary_tree as dt
import folgezettel as fz
import note_format_v2 as nf


def put(root, name, title, body, extra=""):
    (root / name).write_text(f"---\ntitle: {title}\n{extra}---\n\n# {title}\n\n" + "\n".join(body) + "\n", encoding="utf-8")


class DiaryTreeTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def read(self, name):
        return (self.root / name).read_text(encoding="utf-8")

    def test_migrate_and_ids(self):
        r = self.root
        g = "attribute: group\n"
        put(r, "index.md", "Index", ["[時系列記録](rec.md)", "[A](a.md)"], g)
        put(r, "rec.md", "時系列記録", ["Group:", "[Index](index.md)", "", "[日記](diary.md)", "[夢](dream.md)"], g)
        put(r, "diary.md", "日記", ["Group:", "[時系列記録](rec.md)", "", "[2026-10](m.md)"], g)
        put(r, "m.md", "2026-10", ["Group:", "[日記](diary.md)", "", "[2026-10-19-MO-x](d1.md)", "[2026-10-20-TU](d2.md)"], g)
        put(r, "d1.md", "2026-10-19-MO-x", ["Group:", "[2026-10](m.md)", "[A](a.md)", "", "本文。"], 'folgezettel: "7"\n')
        put(r, "d2.md", "2026-10-20-TU", ["Group:", "[2026-10](m.md)", "", "本文。"], 'folgezettel: "8"\n')
        put(r, "kid.md", "子", ["ParentBranch:", "[2026-10-19-MO-x](d1.md)", "", "子の本文。"], 'folgezettel: "7a"\n')
        put(r, "dream.md", "夢", ["Group:", "[時系列記録](rec.md)", "", "[2026-10-夢](dm.md)"], g)
        put(r, "dm.md", "2026-10-夢", ["Group:", "[夢](dream.md)", "", "[2026-10-19-MO-夢](dd.md)"], g)
        put(r, "dd.md", "2026-10-19-MO-夢", ["Group:", "[2026-10-夢](dm.md)", "", "夢の本文。"], 'record: "夢"\n')
        put(r, "a.md", "A", ["本文A。"], g)
        res = dt.migrate(r)
        self.assertTrue(res["ok"])
        for n in ("rec.md", "diary.md", "m.md", "dream.md", "dm.md"):
            self.assertIn("timeline: true", self.read(n))
            self.assertNotIn("attribute: group", self.read(n))
        self.assertIn("ParentBranch:\n[時系列記録](rec.md)", self.read("diary.md"))
        self.assertIn("ParentBranch:\n[日記](diary.md)", self.read("m.md"))
        d1 = self.read("d1.md")
        self.assertIn("Group:\n[A](a.md)\nParentBranch:\n[2026-10](m.md)", d1)   # 別のグループの所属は残す
        self.assertIn("ParentBranch:\n[2026-10-夢](dm.md)", self.read("dd.md"))
        self.assertNotIn("ParentBranch", self.read("rec.md"))                      # Index は親にしない
        self.assertEqual(dt.migrate(r)["changed"], [])                              # 2 回目は何もしない
        nf.simple_sync(r)
        self.assertTrue(bo.check(r)["ok"])
        ids = {n: fz.value(self.read(n)) for n in ("rec.md", "diary.md", "m.md", "d1.md", "d2.md", "kid.md", "dream.md", "dm.md", "dd.md")}
        self.assertEqual(ids["diary.md"], ids["rec.md"] + "a")
        self.assertEqual(ids["m.md"], ids["diary.md"] + "1")
        self.assertEqual([ids["d1.md"], ids["d2.md"]], [ids["m.md"] + "a", ids["m.md"] + "b"])
        self.assertEqual(ids["kid.md"], ids["d1.md"] + "1")
        self.assertEqual(ids["dd.md"], ids["dm.md"] + "a")


if __name__ == "__main__":
    unittest.main()
