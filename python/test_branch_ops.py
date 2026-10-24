#!/usr/bin/env python3
"""Branch（ParentBranch / ChildBranch）の回帰試験。一時フォルダ（~/Desktop/test）だけを使う。

    python3 python/test_branch_ops.py
"""
from __future__ import annotations

import hashlib
import json
import os
import shutil
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))
import branch_ops as bo  # noqa: E402
import note_format_v2 as nf  # noqa: E402

TMP_BASE = os.environ.get("TMPDIR") or str(Path.home() / "Desktop" / "test")


def note(title: str, body: str = "", extra_fm: str = "", sections: str = "") -> str:
    fm = f"---\ntime: 2026-01-01 00:00:00\n{extra_fm}---\n"
    return fm + f"\n# {title}\n\n{body}\n" + sections


class Base(unittest.TestCase):
    def setUp(self) -> None:
        os.makedirs(TMP_BASE, exist_ok=True)
        self.root = Path(tempfile.mkdtemp(dir=TMP_BASE, prefix="branch-"))
        self.addCleanup(shutil.rmtree, self.root, True)
        self.env_backup = os.environ.pop("GNOSIS_SYNC_GUARD_DIR", None)
        self.addCleanup(self._restore_env)

    def _restore_env(self) -> None:
        os.environ.pop("GNOSIS_SYNC_GUARD_DIR", None)
        if self.env_backup is not None:
            os.environ["GNOSIS_SYNC_GUARD_DIR"] = self.env_backup

    def w(self, name: str, text: str) -> Path:
        p = self.root / name
        p.write_text(text, encoding="utf-8")
        return p

    def r(self, name: str) -> str:
        return (self.root / name).read_text(encoding="utf-8")

    def snap(self) -> dict[str, str]:
        return {p.name: p.read_text(encoding="utf-8") for p in self.root.glob("*.md")}

    def add(self, parent: str, *children: str, **kw) -> dict:
        return bo.add_branches(self.root, self.root / parent, [self.root / c for c in children], **kw)

    def sync(self) -> None:
        nf.simple_sync(self.root)


class TestAdd(Base):
    def test_creates_both_sides_and_keeps_body(self) -> None:
        a = note("ノートA", "本文A。\n\n```\nChildBranch:\n[fake](zzz.md)\n```\n")
        b = note("ノートB", "本文B。")
        self.w("a.md", a)
        self.w("b.md", b)
        res = self.add("a.md", "b.md")
        self.assertTrue(res["ok"], res)
        self.assertEqual(res["code"], "added")
        # 本文は 1 バイトも変わらない。本文の末尾の空行 1 つはそのまま節との間の空行になる
        self.assertEqual(self.r("a.md"), a + "ChildBranch:\n[ノートB](b.md)\n")
        # ParentBranch: は本文の上の先頭のブロック（H1 の直後。本文との間に空行 1 つ）
        self.assertEqual(self.r("b.md"), b.replace("# ノートB\n\n", "# ノートB\n\nParentBranch:\n[ノートA](a.md)\n\n", 1))

    def test_one_parent_many_children(self) -> None:
        for n in "abcd":
            self.w(f"{n}.md", note(n.upper()))
        self.assertTrue(self.add("a.md", "b.md")["ok"])
        self.assertTrue(self.add("a.md", "c.md", "d.md")["ok"])
        a = self.r("a.md")
        for n in "BCD":
            self.assertEqual(a.count(f"[{n}]({n.lower()}.md)"), 1)
        self.assertEqual(a.count("ChildBranch:"), 1)
        for n in "bcd":
            self.assertEqual(self.r(f"{n}.md").count("ParentBranch:\n[A](a.md)"), 1)
        self.assertTrue(bo.check(self.root)["ok"])

    def test_second_parent_rejected_nothing_changes(self) -> None:
        for n in "abc":
            self.w(f"{n}.md", note(n.upper()))
        self.assertTrue(self.add("a.md", "b.md")["ok"])
        before = self.snap()
        res = self.add("c.md", "b.md")
        self.assertFalse(res["ok"])
        self.assertEqual(res["code"], "has_parent")
        self.assertEqual(res["parent_title"], "A")  # 現在の親のタイトルを知らせる
        self.assertEqual(res["title"], "B")
        self.assertEqual(self.snap(), before)  # どちらのノートも（親 A も）変更しない

    def test_batch_with_one_bad_child_is_all_or_nothing(self) -> None:
        for n in "abcd":
            self.w(f"{n}.md", note(n.upper()))
        self.assertTrue(self.add("a.md", "b.md")["ok"])
        before = self.snap()
        res = self.add("c.md", "d.md", "b.md")  # d は足せるが b には親 A がいる
        self.assertFalse(res["ok"])
        self.assertEqual(self.snap(), before)

    def test_same_relation_is_not_duplicated(self) -> None:
        self.w("a.md", note("A"))
        self.w("b.md", note("B"))
        self.assertTrue(self.add("a.md", "b.md")["ok"])
        before = self.snap()
        res = self.add("a.md", "b.md")
        self.assertTrue(res["ok"])
        self.assertEqual(res["code"], "already")
        self.assertEqual(self.snap(), before)

    def test_self_reference_rejected(self) -> None:
        self.w("a.md", note("A"))
        before = self.snap()
        res = self.add("a.md", "a.md")
        self.assertEqual((res["ok"], res["code"]), (False, "self"))
        self.assertEqual(self.snap(), before)

    def test_cycles_rejected(self) -> None:
        for n in "abc":
            self.w(f"{n}.md", note(n.upper()))
        self.assertTrue(self.add("a.md", "b.md")["ok"])
        self.assertTrue(self.add("b.md", "c.md")["ok"])
        before = self.snap()
        for parent, child in (("c.md", "a.md"), ("b.md", "a.md")):
            res = self.add(parent, child)
            self.assertFalse(res["ok"], (parent, child))
            self.assertIn(res["code"], ("cycle", "has_parent"))
        # A→B→C→A は、A に親が無いので「循環」で拒否される
        self.assertEqual(self.add("c.md", "a.md")["code"], "cycle")
        self.assertEqual(self.snap(), before)

    def test_index_and_missing_rejected(self) -> None:
        self.w("index.md", "---\ntitle: Index\nattribute: group\n---\n\n# Index\n")
        self.w("a.md", note("A"))
        before = self.snap()
        self.assertEqual(self.add("a.md", "index.md")["code"], "index")
        self.assertEqual(self.add("index.md", "a.md")["code"], "index")
        self.assertEqual(self.add("a.md", "nothing.md")["code"], "missing")
        self.assertEqual(self.snap(), before)

    def test_order_with_existing_sections(self) -> None:
        a = note("A", "本文A", sections="### Context\n[X](x.md)\n### Group\n[G](g.md)\nRelated:\n[R](r.md)\nBackLink:\n[Z](z.md)\n")
        self.w("a.md", a)
        self.w("b.md", note("B", sections="### Context\n[X](x.md)\nBackLink:\n[Y](y.md)\n"))
        self.assertTrue(self.add("a.md", "b.md")["ok"])
        marks = [ln for ln in self.r("a.md").split("\n") if ln in ("### Context", "### Group", "ParentBranch:", "ChildBranch:", "Related:", "BackLink:")]
        self.assertEqual(marks, ["### Context", "### Group", "ChildBranch:", "Related:", "BackLink:"])
        marks = [ln for ln in self.r("b.md").split("\n") if ln in ("### Context", "### Group", "ParentBranch:", "ChildBranch:", "Related:", "BackLink:")]
        self.assertEqual(marks, ["ParentBranch:", "### Context", "BackLink:"])
        # 既存の節の中身は 1 行も変わらない
        self.assertIn("### Context\n[X](x.md)\n### Group\n[G](g.md)\nChildBranch:\n[B](b.md)\nRelated:\n[R](r.md)", self.r("a.md"))

    def test_code_fence_headings_are_not_sections(self) -> None:
        b = note("B", "```\nParentBranch:\n[fake](zzz.md)\n```\n\n~~~\nChildBranch:\n[fake2](yyy.md)\n~~~\n")
        self.w("a.md", note("A"))
        self.w("b.md", b)
        self.w("c.md", note("C"))
        # コードブロック内の偽の ParentBranch は親として数えない
        self.assertTrue(self.add("a.md", "b.md")["ok"])
        out = self.r("b.md")
        # 本物の ParentBranch: は H1 の直後の先頭のブロックに入り、コードブロックの中は 1 バイトも変わらない
        self.assertEqual(out, b.replace("# B\n\n", "# B\n\nParentBranch:\n[A](a.md)\n\n", 1))
        self.assertTrue(bo.check(self.root)["ok"])

    def test_one_sided_state_is_completed_not_duplicated(self) -> None:
        self.w("a.md", note("A", sections="ChildBranch:\n[B](b.md)\n"))
        b = note("B")
        self.w("b.md", b)
        a = self.r("a.md")
        res = self.add("a.md", "b.md")
        self.assertTrue(res["ok"])
        self.assertEqual(self.r("a.md"), a)  # 既にある側は触らない
        self.assertIn("ParentBranch:\n[A](a.md)", self.r("b.md"))

    def test_manual_multiple_parents_is_an_error_and_not_resolved(self) -> None:
        self.w("a.md", note("A"))
        self.w("c.md", note("C"))
        self.w("b.md", note("B", sections="ParentBranch:\n[A](a.md)\n[C](c.md)\n"))
        self.w("d.md", note("D"))
        report = bo.check(self.root)
        self.assertFalse(report["ok"])
        self.assertEqual(report["multi_parent"][0]["note"], "b.md")
        before = self.snap()
        res = self.add("d.md", "b.md")
        self.assertEqual(res["code"], "multi_parent")
        self.sync()
        self.sync()
        out = self.r("b.md")
        self.assertIn("[A](a.md)", out)  # どちらの親も勝手に消さない
        self.assertIn("[C](c.md)", out)
        self.assertEqual(self.r("d.md"), before["d.md"])

    def test_no_inference_from_identifiers(self) -> None:
        self.w("n1.md", note("1"))
        self.w("n1a.md", note("1a"))
        self.w("n2.md", note("2"))
        self.assertTrue(bo.check(self.root)["ok"])
        self.assertTrue(self.add("n2.md", "n1a.md")["ok"])  # 1a は 1 の子と決めつけない
        self.assertNotIn("Branch", self.r("n1.md"))


class TestAtomic(Base):
    def test_second_write_failure_rolls_back_first(self) -> None:
        self.w("a.md", note("A"))
        self.w("b.md", note("B"))
        before = self.snap()
        real_replace = os.replace
        calls = {"n": 0}

        def flaky(src, dst, *a, **k):
            calls["n"] += 1
            if calls["n"] == 2:
                raise OSError("disk full")
            return real_replace(src, dst, *a, **k)

        with mock.patch.object(bo.os, "replace", flaky):
            res = self.add("a.md", "b.md")
        self.assertFalse(res["ok"])
        self.assertEqual(res["code"], "error")
        self.assertEqual(self.snap(), before)  # 片側だけ更新された状態を残さない
        self.assertEqual([p.name for p in self.root.iterdir() if p.name.endswith(".tmp")], [])

    def test_concurrent_edit_detected_and_nothing_replaced(self) -> None:
        a = self.w("a.md", note("A"))
        b = self.w("b.md", note("B"))
        old_a, old_b = a.read_text(encoding="utf-8"), b.read_text(encoding="utf-8")
        b.write_text(old_b + "\n他のプロセスが書いた追記\n", encoding="utf-8")
        with self.assertRaises(RuntimeError) as cm:
            bo._atomic_pair_write([(a, old_a, old_a + "X\n"), (b, old_b, old_b + "Y\n")])
        self.assertTrue(str(cm.exception).startswith("conflict:"))
        self.assertEqual(a.read_text(encoding="utf-8"), old_a)
        self.assertIn("他のプロセスが書いた追記", b.read_text(encoding="utf-8"))
        self.assertNotIn("Y", b.read_text(encoding="utf-8").replace("他のプロセスが書いた追記", ""))

    def test_unsaved_editor_buffer_blocks(self) -> None:
        self.w("a.md", note("A"))
        b = self.w("b.md", note("B"))
        guard = self.root / "guard"
        guard.mkdir()
        digest = hashlib.sha256(str(b.resolve()).encode()).hexdigest()[:16]
        (guard / f"{digest}.{os.getpid()}.dirty").write_text("", encoding="utf-8")
        os.environ["GNOSIS_SYNC_GUARD_DIR"] = str(guard)
        before = self.snap()
        res = self.add("a.md", "b.md")
        self.assertEqual((res["ok"], res["code"]), (False, "dirty"))
        self.assertEqual(self.snap(), before)


class TestSync(Base):
    def test_sync_keeps_branch_sections_and_is_idempotent(self) -> None:
        self.w("a.md", note("A", "本文A [Z](z.md)", sections="### Context\n[X](x.md)\n"))
        self.w("b.md", note("B", "本文B"))
        self.w("c.md", note("C", "本文C"))
        self.w("x.md", note("X"))
        self.w("z.md", note("Z"))
        self.assertTrue(self.add("a.md", "b.md", "c.md")["ok"])
        self.sync()
        first = self.snap()
        self.sync()
        self.assertEqual(self.snap(), first)  # 冪等
        a, b = first["a.md"], first["b.md"]
        self.assertEqual(a.count("[B](b.md)"), 1)
        self.assertEqual(a.count("[C](c.md)"), 1)
        self.assertEqual(b.count("[A](a.md)"), 1)
        # ChildBranch / ParentBranch が Context に変換されない・BackLink に出ない
        self.assertIn("ChildBranch:\n[B](b.md)\n[C](c.md)", a)
        self.assertIn("ParentBranch:\n[A](a.md)", b)
        self.assertNotIn("### Context", b)
        self.assertNotIn("BackLink:", b)
        self.assertIn("### Context\n[X](x.md)\nChildBranch:", a)
        self.assertTrue(bo.check(self.root)["ok"])

    def test_sync_does_not_add_second_parent(self) -> None:
        self.w("a.md", note("A"))
        self.w("b.md", note("B"))
        self.assertTrue(self.add("a.md", "b.md")["ok"])
        self.w("c.md", note("C", "C の本文から [B](b.md) を引用する"))
        self.sync()
        self.sync()
        b = self.r("b.md")
        self.assertEqual(b.count("[A](a.md)"), 1)
        self.assertIn("ParentBranch:\n[A](a.md)", b)
        self.assertEqual(b.count("ParentBranch:"), 1)
        # C は本文リンクなので BackLink に出る（親にはならない）
        self.assertIn("BackLink:\n[C](c.md)", b)
        self.assertNotIn("(c.md)", b.split("BackLink:")[0])
        self.assertTrue(bo.check(self.root)["ok"])

    def test_sync_follows_titles_and_prunes_deleted(self) -> None:
        self.w("a.md", note("A"))
        self.w("b.md", note("B"))
        self.assertTrue(self.add("a.md", "b.md")["ok"])
        self.w("b.md", self.r("b.md").replace("# B\n", "# B改\n"))
        self.sync()
        self.assertIn("[B改](b.md)", self.r("a.md"))
        (self.root / "b.md").unlink()
        self.sync()
        self.assertNotIn("b.md", self.r("a.md"))
        self.assertNotIn("ChildBranch", self.r("a.md"))  # 空になった節は見出しごと消える

    def test_sync_leaves_unrelated_notes_alone(self) -> None:
        self.w("a.md", note("A"))
        self.w("b.md", note("B"))
        other = note("無関係", "そのまま", sections="### Context\n[A](a.md)\n")
        self.w("o.md", other)
        self.sync()
        other_after = self.r("o.md")
        self.assertTrue(self.add("a.md", "b.md")["ok"])
        self.sync()
        self.assertEqual(self.r("o.md"), other_after)


def _worker(args):
    root, guard, parent, child = args
    os.environ["GNOSIS_SYNC_GUARD_DIR"] = guard
    r = bo.add_branches(root, parent, [child])
    return r["code"]


def _sync_worker(args):
    root, guard = args
    os.environ["GNOSIS_SYNC_GUARD_DIR"] = guard
    return nf.simple_sync(root)


class TestVaultLock(Base):
    def setUp(self) -> None:
        super().setUp()
        self.guard = self.root / "state" / "sync-dirty"
        self.guard.mkdir(parents=True)
        os.environ["GNOSIS_SYNC_GUARD_DIR"] = str(self.guard)

    def test_same_vault_is_serialized_other_vaults_are_independent(self) -> None:
        other = Path(tempfile.mkdtemp(dir=TMP_BASE, prefix="branch-other-"))
        self.addCleanup(shutil.rmtree, other, True)
        with nf.vault_lock(self.root, 1.0) as got:
            self.assertTrue(got)
            with nf.vault_lock(other, 1.0) as got_other:  # 別の vault は待たされない
                self.assertTrue(got_other)
            with nf.vault_lock(self.root, 0.3) as got_again:  # 同じ vault は待ち、取れない
                self.assertFalse(got_again)
        with nf.vault_lock(self.root, 1.0) as got_after:  # 解放後は取れる
            self.assertTrue(got_after)

    def test_lock_is_released_when_the_owner_process_dies(self) -> None:
        import subprocess
        code = (
            "import os, sys, time\n"
            f"sys.path.insert(0, {str(Path(__file__).resolve().parent)!r})\n"
            "import note_format_v2 as nf\n"
            f"os.environ['GNOSIS_SYNC_GUARD_DIR'] = {str(self.guard)!r}\n"
            f"cm = nf.vault_lock({str(self.root)!r}, 5)\n"
            "cm.__enter__()\n"
            "print('locked', flush=True)\n"
            "time.sleep(60)\n"
        )
        p = subprocess.Popen([sys.executable, "-c", code], stdout=subprocess.PIPE, text=True)
        try:
            self.assertEqual(p.stdout.readline().strip(), "locked")
            with nf.vault_lock(self.root, 0.3) as got:
                self.assertFalse(got)
            p.kill()  # 異常終了
            p.wait()
            with nf.vault_lock(self.root, 3.0) as got:
                self.assertTrue(got, "異常終了したプロセスのロックが残っている")
        finally:
            if p.poll() is None:
                p.kill()
                p.wait()

    def test_concurrent_branch_adds_and_syncs_lose_nothing(self) -> None:
        import multiprocessing as mp
        self.w("a.md", note("A", "本文A"))
        kids = [f"k{i}.md" for i in range(6)]
        for k in kids:
            self.w(k, note(k[:-3].upper(), f"本文{k}"))
        jobs = [(str(self.root), str(self.guard), str(self.root / "a.md"), str(self.root / k)) for k in kids]
        with mp.get_context("fork").Pool(6) as pool:
            sync_res = pool.map_async(_sync_worker, [(str(self.root), str(self.guard))] * 4)
            codes = pool.map(_worker, jobs)
            sync_res.get(60)
        self.assertEqual(sorted(set(codes)), ["added"], codes)
        a = self.r("a.md")
        for k in kids:
            self.assertEqual(a.count(f"({k})"), 1, a)
            self.assertIn("ParentBranch:\n[A](a.md)", self.r(k))
        self.assertEqual(a.count("ChildBranch:"), 1)
        self.sync()
        self.assertTrue(bo.check(self.root)["ok"])


class TestCli(Base):
    def test_cli_json(self) -> None:
        import subprocess
        self.w("a.md", note("A"))
        self.w("b.md", note("B"))
        script = str(Path(__file__).resolve().parent / "branch_ops.py")
        p = subprocess.run([sys.executable, script, "add", str(self.root), str(self.root / "a.md"), str(self.root / "b.md")],
                           capture_output=True, text=True)
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertEqual(json.loads(p.stdout)["code"], "added")
        p = subprocess.run([sys.executable, script, "check", str(self.root)], capture_output=True, text=True)
        self.assertEqual(p.returncode, 0)
        self.assertTrue(json.loads(p.stdout)["ok"])
        p = subprocess.run([sys.executable, script, "add", str(self.root), str(self.root / "b.md"), str(self.root / "a.md")],
                           capture_output=True, text=True)
        self.assertEqual(p.returncode, 1)
        self.assertEqual(json.loads(p.stdout)["code"], "cycle")



class TestTimelineTree(unittest.TestCase):
    """時系列の木（timeline: true）のノートは、本文に子の一覧があれば、ChildBranch: には重ねて書かない（二重にしない）。"""

    def setUp(self) -> None:
        import tempfile
        base = os.environ.get("TMPDIR") or str(Path.home() / "Desktop" / "test")
        os.makedirs(base, exist_ok=True)
        self.tmp = tempfile.TemporaryDirectory(dir=base)
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        (self.root / "index.md").write_text("---\ntime: x\n---\n\n# Index\n", encoding="utf-8")

    def test_children_in_body_are_not_repeated_in_child_branch(self) -> None:
        r = self.root
        (r / "m.md").write_text("---\ntime: x\ntimeline: true\n---\n\n# 2026-10\n\n[2026-10-02-FR](d2.md)\n[2026-10-01-TH](d1.md)\n", encoding="utf-8")
        for n, t in (("d1", "2026-10-01-TH"), ("d2", "2026-10-02-FR")):
            (r / f"{n}.md").write_text(f"---\ntime: x\n---\n\n# {t}\n\nParentBranch:\n[2026-10](m.md)\n\n本文\n", encoding="utf-8")
        nf.simple_sync(r)
        m = (r / "m.md").read_text(encoding="utf-8")
        self.assertNotIn("ChildBranch:", m)   # 本文の一覧があるので重ねて書かない
        self.assertIn("[2026-10-02-FR](d2.md)\n[2026-10-01-TH](d1.md)\n", m)   # 本文の一覧はそのまま
        # すでに二重になっているノートは、本文の一覧だけを残す
        (r / "m.md").write_text(m + "\nChildBranch:\n[2026-10-01-TH](d1.md)\n[2026-10-02-FR](d2.md)\n", encoding="utf-8")
        nf.simple_sync(r)
        self.assertNotIn("ChildBranch:", (r / "m.md").read_text(encoding="utf-8"))
        self.assertEqual(nf.simple_sync(r), 0)   # 2 回目は変わらない

    def test_ordinary_note_keeps_body_as_the_list(self) -> None:
        r = self.root
        (r / "m.md").write_text("---\ntime: x\n---\n\n# 親\n\n[子](d1.md)\n", encoding="utf-8")
        (r / "d1.md").write_text("---\ntime: x\n---\n\n# 子\n\nParentBranch:\n[親](m.md)\n\n本文\n", encoding="utf-8")
        nf.simple_sync(r)
        self.assertNotIn("ChildBranch:", (r / "m.md").read_text(encoding="utf-8"))


class TestParentBranchDeletion(unittest.TestCase):
    """子の ParentBranch: を手で消せば、親の ChildBranch: からも外れる（片側だけ手で書いた ChildBranch: は残る）。"""

    def setUp(self) -> None:
        import tempfile
        base = os.environ.get("TMPDIR") or str(Path.home() / "Desktop" / "test")
        os.makedirs(base, exist_ok=True)
        self.tmp = tempfile.TemporaryDirectory(dir=base)
        self.addCleanup(self.tmp.cleanup)
        self.root = r = Path(self.tmp.name)
        (r / "index.md").write_text("---\ntime: x\n---\n\n# Index\n", encoding="utf-8")
        (r / "p.md").write_text("---\ntime: x\n---\n\n# 親\n\n本文\n\nChildBranch:\n[子](c.md)\n", encoding="utf-8")
        (r / "c.md").write_text("---\ntime: x\n---\n\n# 子\n\nParentBranch:\n[親](p.md)\n\n本文\n", encoding="utf-8")
        nf.simple_sync(r)
        nf.simple_sync(r)

    def test_deleting_parent_branch_detaches(self) -> None:
        r = self.root
        (r / "c.md").write_text("---\ntime: x\n---\n\n# 子\n\n本文\n", encoding="utf-8")
        nf.simple_sync(r)
        self.assertNotIn("ChildBranch:", (r / "p.md").read_text(encoding="utf-8"))
        self.assertNotIn("ParentBranch:", (r / "c.md").read_text(encoding="utf-8"))   # 子に戻ってこない
        for _ in range(2):                                                          # 何度同期しても戻らない・変わらない
            nf.simple_sync(r)
        self.assertNotIn("ChildBranch:", (r / "p.md").read_text(encoding="utf-8"))

    def test_one_sided_hand_written_child_branch_stays(self) -> None:
        r = self.root
        (r / "q.md").write_text("---\ntime: x\n---\n\n# 別\n\n本文\n\nChildBranch:\n[子](c.md)\n", encoding="utf-8")
        for _ in range(3):
            nf.simple_sync(r)
        self.assertIn("ChildBranch:\n[子](c.md)", (r / "q.md").read_text(encoding="utf-8"))

    def test_deleting_from_parent_side_does_not_detach(self) -> None:
        r = self.root
        (r / "p.md").write_text("---\ntime: x\n---\n\n# 親\n\n本文\n", encoding="utf-8")
        nf.simple_sync(r)
        self.assertIn("ParentBranch:\n[親](p.md)", (r / "c.md").read_text(encoding="utf-8"))
        self.assertIn("[子](c.md)", (r / "p.md").read_text(encoding="utf-8"))   # 子の ParentBranch: があるので戻る

if __name__ == "__main__":
    unittest.main(verbosity=1)
