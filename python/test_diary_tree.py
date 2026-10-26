"""日記と時系列記録の木（グループ → 普通のノート＋ParentBranch:）の移行の回帰網。"""
import tempfile
import unittest
from unittest import mock
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


class RecordRenameTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        r = self.root
        tl = "timeline: true\n"
        put(r, "index.md", "Index", ["[時系列記録](rec.md)"], "attribute: group\n")
        put(r, "rec.md", "時系列記録", ["[夢](dream.md)", "[日記](diary.md)"], tl)
        put(r, "dream.md", "夢", ["ParentBranch:", "[時系列記録](rec.md)"], tl)
        put(r, "year.md", "2026-夢", ["ParentBranch:", "[夢](dream.md)", "", "[2026-10-夢](month.md)"], tl)
        put(r, "month.md", "2026-10-夢", ["ParentBranch:", "[2026-夢](year.md)", "", "[2026-10-19-MO-夢](day.md)"], tl)
        put(r, "day.md", "2026-10-19-MO-夢", ["ParentBranch:", "[2026-10-夢](month.md)", "", "本文。"], 'record: "夢"\n')
        put(r, "diary.md", "日記", ["ParentBranch:", "[時系列記録](rec.md)"], tl)
        put(r, "diary-month.md", "2026-10", ["ParentBranch:", "[日記](diary.md)"], tl)
        put(r, "memo.md", "メモ-夢", ["ParentBranch:", "[2026-夢](year.md)"])
        put(r, "outside.md", "2025-夢", ["本文。"], tl)

    def snapshot(self):
        return {p.name: p.read_bytes() for p in self.root.glob("*.md")}

    def read(self, name):
        return (self.root / name).read_text(encoding="utf-8")

    def test_rename_dates_and_repeat(self):
        before = self.snapshot()
        preview = dt.rename_kind(self.root, "夢", "夢日記", dry_run=True)
        self.assertTrue(preview["ok"])
        self.assertEqual(preview["counts"], {"year": 1, "month": 1, "day": 1})
        self.assertEqual(self.snapshot(), before)
        result = dt.rename_kind(self.root, "夢", "夢日記")
        self.assertTrue(result["ok"])
        for name, title in [("dream.md", "夢日記"), ("year.md", "2026-夢日記"),
                            ("month.md", "2026-10-夢日記"), ("day.md", "2026-10-19-MO-夢日記")]:
            self.assertEqual(bo.note_title(self.read(name), self.root / name), title)
        self.assertIn('record: "夢日記"', self.read("day.md"))
        for name in ["memo.md", "outside.md", "diary-month.md"]:
            self.assertEqual((self.root / name).read_bytes(), before[name])
        self.assertEqual(dt.rename_kind(self.root, "夢", "夢日記")["changed"], [])
        self.assertEqual(dt.rename_kind(self.root, "夢日記", "夢日記")["changed"], [])

    def test_kind_only(self):
        before = self.snapshot()
        result = dt.rename_kind(self.root, "夢", "夢日記", include_descendants=False)
        self.assertTrue(result["ok"])
        self.assertEqual(result["changed"], [str(self.root / "dream.md")])
        self.assertEqual(self.read("month.md").encode(), before["month.md"])

    def test_collisions_are_rejected_without_writing(self):
        put(self.root, "other.md", "筋トレ", ["ParentBranch:", "[時系列記録](rec.md)"], "timeline: true\n")
        for title in ["筋トレ", "日記", "時系列記録"]:
            with self.subTest(title=title):
                before = self.snapshot()
                result = dt.rename_kind(self.root, "夢", title)
                self.assertFalse(result["ok"])
                self.assertEqual(result["code"], "collision")
                self.assertEqual(self.snapshot(), before)

    def test_diary_and_timeline_are_protected(self):
        before = self.snapshot()
        for old in ["日記", "時系列記録"]:
            result = dt.rename_kind(self.root, old, "別の名前")
            self.assertFalse(result["ok"])
            self.assertEqual(result["code"], "protected")
        self.assertEqual(self.snapshot(), before)

    def test_only_direct_kinds_are_applicable(self):
        result = dt.rename_kind(self.root, "2026-夢", "ほか", kind_file=self.root / "year.md")
        self.assertFalse(result["applicable"])
        self.assertEqual(result["changed"], [])

    def test_childbranch_only_and_regex_names(self):
        put(self.root, "child-only.md", "2027-夢", ["本文。"], "timeline: true\n")
        with (self.root / "dream.md").open("a") as f:
            f.write("\nChildBranch:\n[2027-夢](child-only.md)\n")
        result = dt.rename_kind(self.root, "夢", "夢[.*]")
        self.assertTrue(result["ok"])
        self.assertIn("# 2027-夢[.*]", self.read("child-only.md"))
        self.assertTrue(dt.rename_kind(self.root, "夢[.*]", "夢日記")["ok"])
        self.assertIn("# 2027-夢日記", self.read("child-only.md"))

    def test_atomic_failure_restores_all_titles(self):
        before = self.snapshot()
        replace = bo.os.replace
        calls = []
        def fail_second(src, dst):
            calls.append(dst)
            if len(calls) == 2:
                raise OSError("simulated write failure")
            return replace(src, dst)
        with mock.patch.object(bo.os, "replace", side_effect=fail_second):
            result = dt.rename_kind(self.root, "夢", "夢日記")
        self.assertFalse(result["ok"])
        self.assertEqual(result["changed"], [])
        self.assertEqual(self.snapshot(), before)

    def test_existing_sync_updates_links_preserving_handwritten_labels(self):
        put(self.root, "custom.md", "Custom", ["[手書き名](day.md)"])
        result = dt.rename_kind(self.root, "夢", "夢日記")
        nf.simple_sync(self.root, {e["path"]: e["old"] for e in result["entries"]})
        self.assertIn("[2026-10-夢日記](month.md)", self.read("year.md"))
        self.assertIn("[2026-10-19-MO-夢日記](day.md)", self.read("month.md"))
        self.assertIn("[手書き名](day.md)", self.read("custom.md"))


if __name__ == "__main__":
    unittest.main()
