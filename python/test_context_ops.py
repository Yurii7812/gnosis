#!/usr/bin/env python3
"""Context ブロック（`Context:` + 直下のリンク）の回帰試験。一時フォルダ（~/gnosis-work/test）だけを使う。"""
from __future__ import annotations

import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import branch_ops as bo  # noqa: E402
import context_ops as co  # noqa: E402
import note_format_v2 as nf  # noqa: E402

TMP_BASE = os.environ.get("TMPDIR") or str(Path.home() / "gnosis-work" / "test")


def fm(title: str) -> str:
    return "---\ntime: 2026-01-01 00:00:00\n---\n"


class Base(unittest.TestCase):
    def setUp(self) -> None:
        os.makedirs(TMP_BASE, exist_ok=True)
        self.root = Path(tempfile.mkdtemp(dir=TMP_BASE, prefix="ctx-"))
        self.addCleanup(shutil.rmtree, self.root, True)

    def w(self, name: str, text: str) -> Path:
        p = self.root / name
        p.write_text(text, encoding="utf-8")
        return p

    def r(self, name: str) -> str:
        return (self.root / name).read_text(encoding="utf-8")

    def sync(self) -> None:
        nf.simple_sync(self.root)

    def add(self, name: str, link: str) -> tuple[str, bool]:
        lines = self.r(name).split("\n")[:-1]
        out, added = co.add_link(lines, link, self.root)
        return "\n".join(out) + "\n", added


class TestBlock(Base):
    def test_not_a_heading_and_position(self) -> None:
        t = fm("B") + "\n# B\n\nContext:\n[A](a.md)\n\n本文。\n"
        lines = t.split("\n")
        b = co.find_block(lines)
        self.assertEqual(lines[b[0]], "Context:")
        self.assertFalse(lines[b[0]].startswith("#"))
        self.assertEqual(co.context_links(lines), ["[A](a.md)"])

    def test_add_goes_to_the_end_and_keeps_body(self) -> None:
        t = fm("B") + "\n# B\n\nContext:\n[A](a.md)\n\n本文。\n"
        self.w("b.md", t)
        out, added = self.add("b.md", "[C](c.md)")
        self.assertTrue(added)
        self.assertEqual(out, fm("B") + "\n# B\n\nContext:\n[A](a.md)\n[C](c.md)\n\n本文。\n")

    def test_duplicates_are_not_added_even_with_other_display_name_or_path_form(self) -> None:
        self.w("b.md", fm("B") + "\n# B\n\nContext:\n[A](a.md)\n\n本文。\n")
        self.assertFalse(self.add("b.md", "[別名](a.md)")[1])
        self.assertFalse(self.add("b.md", "[A](./a.md)")[1])

    def test_created_after_h1_when_missing(self) -> None:
        self.w("b.md", fm("B") + "\n# B\n\n本文。\n\nBackLink:\n[Z](z.md)\n")
        out, added = self.add("b.md", "[A](a.md)")
        self.assertTrue(added)
        self.assertEqual(out, fm("B") + "\n# B\n\nContext:\n[A](a.md)\n\n本文。\n\nBackLink:\n[Z](z.md)\n")

    def test_no_context_is_not_invented(self) -> None:
        t = fm("B") + "\n# B\n\n本文。\n"
        self.assertIsNone(co.find_block(t.split("\n")))
        self.w("b.md", t)
        self.sync()
        self.assertNotIn("Context", self.r("b.md"))

    def test_context_in_code_block_is_ignored(self) -> None:
        t = fm("B") + "\n# B\n\n```\nContext:\n[fake](fake.md)\n```\n\n本文。\n"
        self.assertIsNone(co.find_block(t.split("\n")))
        self.w("b.md", t)
        out, added = self.add("b.md", "[A](a.md)")
        self.assertTrue(added)
        self.assertTrue(out.startswith(fm("B") + "\n# B\n\nContext:\n[A](a.md)\n\n```\nContext:\n[fake](fake.md)\n```"))

    def test_context_text_in_prose_is_not_a_block(self) -> None:
        t = fm("B") + "\n# B\n\n本文が先にある。\n\nContext:\n[A](a.md)\n"
        self.assertIsNone(co.find_block(t.split("\n")))


class TestLegacy(Base):
    OLD = fm("A") + "\n# A\n\n本文。\n\n### Context\n[B](b.md)\n[C](c.md)\n\nBackLink:\n[Z](z.md)\n"

    def test_old_form_is_read(self) -> None:
        self.assertEqual(co.context_links(self.OLD.split("\n")), ["[B](b.md)", "[C](c.md)"])

    def test_add_to_old_form_migrates_that_note_without_losing_links(self) -> None:
        self.w("a.md", self.OLD)
        out, added = self.add("a.md", "[D](d.md)")
        self.assertTrue(added)
        self.assertIn("Context:\n[B](b.md)\n[C](c.md)\n[D](d.md)\n", out)
        self.assertNotIn("### Context", out)
        self.assertIn("本文。", out)
        self.assertIn("BackLink:\n[Z](z.md)", out)

    def test_migrate_lines_is_idempotent_and_verified(self) -> None:
        new = co.migrate_text(self.OLD)
        self.assertEqual(new, fm("A") + "\n# A\n\nContext:\n[B](b.md)\n[C](c.md)\n\n本文。\n\nBackLink:\n[Z](z.md)\n")
        self.assertTrue(co.verify_migration(self.OLD, new))
        self.assertEqual(co.migrate_text(new), new)

    def test_both_forms_are_merged_without_losing_links(self) -> None:
        both = fm("A") + "\n# A\n\nContext:\n[B](b.md)\n\n本文。\n\n### Context\n[B](b.md)\n[C](c.md)\n"
        new = co.migrate_text(both)
        self.assertEqual(sorted(co.context_links(new.split("\n"))), ["[B](b.md)", "[C](c.md)"])
        self.assertNotIn("### Context", new)
        self.assertTrue(co.verify_migration(both, new))

    def test_non_link_lines_of_old_section_are_kept(self) -> None:
        t = fm("A") + "\n# A\n\n本文。\n\n### Context\nメモ: あとで読む\n[B](b.md)\n"
        new = co.migrate_text(t)
        self.assertIn("メモ: あとで読む", new)
        self.assertIn("Context:\n[B](b.md)", new)

    def test_sync_does_not_migrate_old_form_and_keeps_links(self) -> None:
        for n in "bcz":
            self.w(f"{n}.md", fm(n.upper()) + f"\n# {n.upper()}\n")
        self.w("a.md", self.OLD)
        before = self.r("a.md")
        self.sync()
        self.sync()
        self.assertIn("### Context\n[B](b.md)\n[C](c.md)", self.r("a.md"))
        self.assertNotIn("Context:", self.r("a.md"))
        self.assertNotIn("\nContext:\n", self.r("a.md"))
        del before

    def test_cli_dry_run_then_apply(self) -> None:
        for n in "bc":
            self.w(f"{n}.md", fm(n.upper()) + f"\n# {n.upper()}\n")
        self.w("a.md", self.OLD)
        script = str(Path(__file__).resolve().parent / "context_ops.py")
        p = subprocess.run([sys.executable, script, "migrate", str(self.root)], capture_output=True, text=True)
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertEqual(self.r("a.md"), self.OLD)  # 試走は書き換えない
        p = subprocess.run([sys.executable, script, "migrate", str(self.root), "--apply"], capture_output=True, text=True)
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertIn("Context:\n[B](b.md)\n[C](c.md)", self.r("a.md"))
        self.assertEqual(self.r("b.md"), fm("B") + "\n# B\n")  # 関係の無いノートは触らない


class TestYomiSort(Base):
    def test_sort_keeps_context_order(self) -> None:
        import japanese_yomi as jy
        lines = ["# T", "", "Context:", "[B](b.md)", "[A](a.md)", "", "[Z](z.md)", "[Y](y.md)", "", "本文"]
        out = jy.sort_lines(lines, self.root)
        self.assertEqual(out[2:5], ["Context:", "[B](b.md)", "[A](a.md)"])  # Context は並べ替えない
        self.assertEqual(out[6:8], ["[Y](y.md)", "[Z](z.md)"])  # 本文のリンクは並べ替える


class TestSyncNewForm(Base):
    def test_new_form_is_kept_idempotent_and_body_untouched(self) -> None:
        self.w("a.md", fm("A") + "\n# A\n\n本文A。\n")
        self.w("c.md", fm("C") + "\n# C\n\n本文C。\n")
        b = fm("B") + "\n# B\n\nContext:\n[A](a.md)\n[C](c.md)\n\n本文B。\n\n[A](a.md) を参照。\n"
        self.w("b.md", b)
        self.sync()
        first = self.r("b.md")
        self.sync()
        self.assertEqual(self.r("b.md"), first)
        self.assertIn("\nContext:\n[A](a.md)\n[C](c.md)\n\n本文B。", first)
        self.assertNotIn("### Context", first)
        self.assertNotIn("BackLink:", first)  # Context にいる相手は BackLink に出ない

    def test_context_links_follow_titles_and_dangling_are_pruned(self) -> None:
        self.w("a.md", fm("A") + "\n# A\n")
        self.w("b.md", fm("B") + "\n# B\n\nContext:\n[旧名](a.md)\n[消えた](gone.md)\n\n本文。\n")
        self.sync()
        self.assertIn("Context:\n[A](a.md)\n\n本文。", self.r("b.md"))
        self.assertNotIn("gone.md", self.r("b.md"))

    def test_emptied_block_disappears_cleanly(self) -> None:
        self.w("b.md", fm("B") + "\n# B\n\nContext:\n[消えた](gone.md)\n\n本文。\n")
        self.sync()
        self.assertEqual(self.r("b.md"), fm("B") + "\n# B\n\n本文。\n")

    def test_group_link_moves_to_group_section_and_context_keeps_the_rest(self) -> None:
        self.w("g.md", fm("G") + "attribute: group\n---\n".replace("---\n", "", 0) if False else "---\ntitle: G\nattribute: group\n---\n\n# G\n")
        self.w("a.md", fm("A") + "\n# A\n")
        self.w("b.md", fm("B") + "\n# B\n\nContext:\n[G](g.md)\n[A](a.md)\n\n本文。\n")
        self.sync()
        out = self.r("b.md")
        self.assertIn("Context:\n[A](a.md)\n\n本文。", out)
        self.assertIn("Group:\n[G](g.md)", out)

    def test_parent_branch_and_context_to_same_note_coexist(self) -> None:
        self.w("a.md", fm("A") + "\n# A\n\n本文A。\n")
        self.w("b.md", fm("B") + "\n# B\n\nContext:\n[A](a.md)\n\n本文B。\n")
        res = bo.add_branches(self.root, self.root / "a.md", [self.root / "b.md"])
        self.assertTrue(res["ok"], res)
        self.sync()
        self.sync()
        b = self.r("b.md")
        self.assertIn("Context:\n[A](a.md)", b)
        self.assertIn("ParentBranch:\n[A](a.md)", b)
        self.assertEqual(b.count("[A](a.md)"), 2)
        self.assertTrue(bo.check(self.root)["ok"])

    def test_parent_branch_still_at_most_one_after_sync(self) -> None:
        for n in "acd":
            self.w(f"{n}.md", fm(n.upper()) + f"\n# {n.upper()}\n")
        self.w("b.md", fm("B") + "\n# B\n\nContext:\n[A](a.md)\n[C](c.md)\n\n本文。\n")
        self.assertTrue(bo.add_branches(self.root, self.root / "a.md", [self.root / "b.md"])["ok"])
        res = bo.add_branches(self.root, self.root / "c.md", [self.root / "b.md"])
        self.assertEqual(res["code"], "has_parent")
        self.sync()
        self.assertEqual(self.r("b.md").count("ParentBranch:"), 1)

    def test_old_cache_is_reparsed(self) -> None:
        self.w("b.md", fm("B") + "\n# B\n\nContext:\n[A](a.md)\n\n本文。\n")
        self.w("a.md", fm("A") + "\n# A\n")
        self.sync()
        import json
        fp = self.root / ".pkm_parse_cache_v2.json"
        data = json.loads(fp.read_text(encoding="utf-8"))
        for k, v in data.items():
            data[k] = v[:11]  # 旧形式のキャッシュ
        fp.write_text(json.dumps(data), encoding="utf-8")
        before = self.r("b.md")
        self.sync()
        self.assertEqual(self.r("b.md"), before)


if __name__ == "__main__":
    unittest.main(verbosity=1)
