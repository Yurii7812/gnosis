#!/usr/bin/env python3
"""Regression for agreed Branch/Context invariants (isolated temporary vault)."""
from __future__ import annotations

import os
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import branch_ops as bo
import folgezettel as fz
import note_format_v2 as nf


def note(title: str, *, fm="", body="", top="", bottom="") -> str:
    return (f"---\ntime: 2026-01-01 00:00:00\n{fm}---\n\n# {title}\n\n"
            + (top + "\n" if top else "")
            + body + ("\n" if body else "")
            + ("\n" + bottom + "\n" if bottom else ""))


class BranchContextRules(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def write(self, file, content):
        p = self.root / file
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(content, encoding="utf-8")
        return p

    def read(self, file):
        return (self.root / file).read_text(encoding="utf-8")

    def parse(self, file):
        p = self.root / file
        return nf._simple_parse_text(p, p.read_text(encoding="utf-8"))

    def sync(self):
        nf.simple_sync(self.root)

    def test_context_duplicates_removed_but_other_context_kept(self):
        self.write("a.md", note("親"))
        self.write("z.md", note("別の文脈"))
        self.write("b.md", note("子", top="ParentBranch:\n[親](a.md)\nContext:\n[親の別名](./a.md)\n[別の文脈](z.md)"))
        self.sync()
        parsed = self.parse("b.md")
        self.assertEqual([t for _d,t in nf._links_from(parsed["pbranch"])], ["a.md"])
        self.assertEqual([t for _d,t in nf._links_from(parsed["ctx"])], ["z.md"])
        self.assertNotIn("親の別名", self.read("b.md"))
        self.assertIn("ChildBranch:\n[子](b.md)", self.read("a.md"))
        snap = (self.read("a.md"), self.read("b.md"))
        self.sync()
        self.assertEqual(snap, (self.read("a.md"), self.read("b.md")))

    def test_sync_restores_zo_outline_display_in_context(self):
        self.write("261031012755.md", note("自分のホームページを作った",
            body="## 相談とか軽作業とかはhaiku\n本文。"))
        self.write("ref.md", note("参照",
            top="Context:\n[自分のホームページを作った](261031012755.md#相談とか軽作業とかはhaiku)"))
        self.sync()
        expected = ("[自分のホームページを作った#相談とか軽作業とかはhaiku]"
                    "(261031012755.md#相談とか軽作業とかはhaiku)")
        self.assertIn(expected, self.read("ref.md"))
        snap = self.read("ref.md")
        self.sync()
        self.assertEqual(self.read("ref.md"), snap)

    def test_sync_restores_zo_heading_in_prose_but_keeps_custom_alias(self):
        self.write("web.md", note("自分のホームページを作った",
            body="## 相談とか軽作業とかはhaiku\n本文。"))
        self.write("ref.md", note("参照",
            body="[自分のホームページを作った](web.md#相談とか軽作業とかはhaiku)\n"
                 "前に[見て](web.md#相談とか軽作業とかはhaiku)ね"))
        self.sync()
        text = self.read("ref.md")
        self.assertIn("[自分のホームページを作った#相談とか軽作業とかはhaiku]"
                      "(web.md#相談とか軽作業とかはhaiku)", text)
        self.assertIn("前に[見て](web.md#相談とか軽作業とかはhaiku)ね", text)
        self.assertEqual(nf.simple_sync(self.root), 0)

    def test_zo_fragment_with_english_slug_and_duplicate_heading(self):
        self.write("web.md", note("Website", body="## Writing a blog\nNotes\n## Memo\nA\n## Memo\nB"))
        self.write("ref.md", note("参照", top="Context:\n"
            "[Website](web.md#writing-a-blog)\n"
            "[Website](web.md#memo-1)"))
        self.sync()
        text = self.read("ref.md")
        self.assertIn("[Website#Writing a blog](web.md#writing-a-blog)", text)
        self.assertIn("[Website#Memo](web.md#memo-1)", text)

    def test_legacy_context_duplicate_is_removed(self):
        self.write("a.md", note("親"))
        self.write("z.md", note("別"))
        self.write("b.md", note("子", top="ParentBranch:\n[親](a.md)", bottom="### Context\n[親](a.md)\n[別](z.md)"))
        self.sync()
        n = self.parse("b.md")
        self.assertNotIn("a.md", [t for _d,t in nf._links_from(n["parent"] + n["ctx"])])
        self.assertIn("z.md", [t for _d,t in nf._links_from(n["parent"] + n["ctx"])])

    def test_explicit_children_also_appear_in_prose_and_are_sorted(self):
        self.write("parent.md", note("親", fm='folgezettel: "1"\n',
                 body="説明の中に既に [後の子](late.md) がある。\n[先の子](early.md)",
                 bottom="ChildBranch:\n[後の子](late.md)\n[先の子](early.md)\n[先の子](early.md)"))
        self.write("early.md", note("先の子", top="ParentBranch:\n[親](parent.md)"))
        self.write("late.md", note("後の子", top="ParentBranch:\n[親](parent.md)"))
        self.sync()
        n = self.parse("parent.md")
        children = [tg for _disp, tg in nf._links_from(n["cbranch"])]
        self.assertEqual(set(children), {"early.md", "late.md"})
        self.assertEqual(len(children), 2)
        # Verify the actual allocated ID ordering, rather than file-name ordering.
        expected = sorted(children, key=lambda c: fz.natural_key(fz.value(self.read(c))))
        self.assertEqual(children, expected)
        self.assertIn("[後の子](late.md)", self.read("parent.md").split("ChildBranch:")[0])
        self.assertIn("[先の子](early.md)", self.read("parent.md").split("ChildBranch:")[0])
        before = self.read("parent.md")
        self.sync()
        self.assertEqual(before, self.read("parent.md"))

    def test_adding_branch_writes_child_even_when_already_in_prose(self):
        self.write("a.md", note("親", body="本文で [子](sub/b.md) を引用する。"))
        self.write("sub/b.md", note("子", top="Context:\n[親](../a.md)"))
        result = bo.add_branches(self.root, self.root / "a.md", [self.root / "sub/b.md"])
        self.assertTrue(result.get("ok"), result)
        self.assertIn("ChildBranch:\n[子](sub/b.md)", self.read("a.md"))
        self.assertIn("ParentBranch:\n[親](../a.md)", self.read("sub/b.md"))
        self.sync()
        self.assertNotIn("Context:\n[親](../a.md)", self.read("sub/b.md"))
        self.assertTrue(bo.check(self.root)["ok"])

    def test_branchgroup_child_not_repeated_and_old_duplicate_removed(self):
        self.write("parent.md", note("親", fm='folgezettel: "1"\n',
            body="BranchGroup:\n[グループ](g.md)\n\n本文に [通常の子](child.md) の記述。",
            bottom="ChildBranch:\n[グループ](g.md)\n[通常の子](child.md)"))
        self.write("g.md", note("グループ", fm="attribute: group\n",
            top="ParentBranch:\n[親](parent.md)"))
        self.write("child.md", note("通常の子", top="ParentBranch:\n[親](parent.md)"))
        self.sync()
        parent = self.read("parent.md")
        self.assertIn("BranchGroup:\n[グループ](g.md)", parent)
        self.assertIn("ChildBranch:\n[通常の子](child.md)", parent)
        child_lines = self.parse("parent.md")["cbranch"]
        self.assertNotIn("g.md", [tg for _d, tg in nf._links_from(child_lines)])
        self.assertEqual([tg for _d, tg in nf._links_from(child_lines)], ["child.md"])
        self.assertIn("ParentBranch:\n[親](parent.md)", self.read("g.md"))
        self.assertTrue(bo.check(self.root)["ok"])
        snap = {name: self.read(name) for name in ("parent.md", "g.md", "child.md")}
        self.sync()
        self.assertEqual(snap, {name: self.read(name) for name in snap})

    def test_branch_ops_avoid_duplicating_existing_branchgroup(self):
        self.write("parent.md", note("親", body="BranchGroup:\n[グループ](g.md)"))
        self.write("g.md", note("グループ", fm="attribute: group\n"))
        result = bo.add_branches(self.root, self.root / "parent.md", [self.root / "g.md"])
        self.assertTrue(result.get("ok"), result)
        self.assertIn("ParentBranch:\n[親](parent.md)", self.read("g.md"))
        self.assertNotIn("ChildBranch:", self.read("parent.md"))
        self.sync()
        self.assertNotIn("ChildBranch:", self.read("parent.md"))
        self.assertTrue(bo.check(self.root)["ok"])

    def test_body_link_alone_does_not_create_branch(self):
        self.write("a.md", note("文章", body="[単なる引用](b.md)"))
        self.write("b.md", note("引用"))
        self.sync()
        self.assertNotIn("ChildBranch:", self.read("a.md"))
        self.assertNotIn("ParentBranch:", self.read("b.md"))

    def test_cross_directory_context_identity_and_id_order(self):
        self.write("a.md", note("親"))
        self.write("sub/c.md", note("子", top="ParentBranch:\n[親](../a.md)\nContext:\n[同じ親](.././a.md)"))
        self.sync()
        self.assertEqual([tg for _d,tg in nf._links_from(self.parse("sub/c.md")["ctx"])], [])


if __name__ == "__main__":
    unittest.main()
