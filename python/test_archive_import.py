#!/usr/bin/env python3
"""archive_import.py の試験（一時フォルダだけを使う。7z が無い環境では飛ばす）。"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import archive_import as ai  # noqa: E402

SEVENZ = ai.find_7z()


@unittest.skipUnless(SEVENZ, "7z が無い")
class T(unittest.TestCase):
    def setUp(self):
        base = os.environ.get("TMPDIR") or str(Path.home() / "gnosis-work" / "test")
        os.makedirs(base, exist_ok=True)
        self.tmp = tempfile.TemporaryDirectory(dir=base)
        t = Path(self.tmp.name)
        self.root = t / "vault"
        self.root.mkdir()
        (self.root / "a.md").write_text("old\n")
        (self.root / "same.md").write_text("hi\n")
        src = t / "src" / "v"
        (src / ".state").mkdir(parents=True)
        (src / "sub").mkdir()
        (src / "a.md").write_text("NEW\n")
        (src / "same.md").write_text("hi\n")
        (src / "sub" / "c.md").write_text("c\n")
        (src / ".state" / "s").write_text("x")
        os.symlink("/etc/passwd", src / "link.md")
        self.plain = t / "plain.zip"
        self.locked = t / "locked.7z"
        subprocess.run([SEVENZ, "a", "-tzip", "-snl", str(self.plain), "v"], cwd=t / "src", check=True, capture_output=True)
        subprocess.run([SEVENZ, "a", "-t7z", "-snl", "-mhe=on", "-ppw", str(self.locked), "v"], cwd=t / "src", check=True, capture_output=True)

    def tearDown(self):
        self.tmp.cleanup()

    def test_plan_and_apply(self):
        p = ai.plan(str(self.root), str(self.plain), None)
        self.assertEqual(p["new"], ["sub/c.md"], p)
        self.assertEqual(p["changed"], ["a.md"], p)
        self.assertEqual(p["same"], ["same.md"], p)
        self.assertEqual((self.root / "a.md").read_text(), "old\n")  # plan では触らない
        r = ai.apply(str(self.root), p["stage"])
        self.assertEqual((r["added"], r["updated"]), (1, 1), r)
        self.assertEqual((self.root / "a.md").read_text(), "NEW\n")
        self.assertEqual((self.root / "sub" / "c.md").read_text(), "c\n")
        self.assertEqual((Path(r["backup"]) / "a.md").read_text(), "old\n")  # 元は残る
        self.assertFalse((self.root / ".state").exists())
        self.assertFalse((self.root / "link.md").exists())
        self.assertFalse(Path(p["stage"]).exists())

    def test_password(self):
        self.assertTrue(ai.plan(str(self.root), str(self.locked), None).get("need_password"))
        bad = ai.plan(str(self.root), str(self.locked), "bad")
        self.assertTrue(bad.get("need_password") and bad.get("wrong"), bad)
        ok = ai.plan(str(self.root), str(self.locked), "pw")
        self.assertEqual(ok["changed"], ["a.md"], ok)
        ai.discard(ok["stage"])
        self.assertFalse(Path(ok["stage"]).exists())

    def _stage(self, files, mtime=None):
        """files {相対パス: 中身(str|bytes)} を書庫の形で並べた展開済みフォルダ（stage）を作る。"""
        stage = Path(tempfile.mkdtemp(prefix=ai.STAGE_PREFIX, dir=self.tmp.name)) / "v"
        for rel, body in files.items():
            f = stage / rel
            f.parent.mkdir(parents=True, exist_ok=True)
            f.write_bytes(body if isinstance(body, bytes) else body.encode())
            if mtime is not None:
                os.utime(f, (mtime, mtime))
        return stage.parent

    def _touch(self, rel, body, mtime):
        f = self.root / rel
        f.parent.mkdir(parents=True, exist_ok=True)
        f.write_text(body)
        os.utime(f, (mtime, mtime))

    def test_replace_removes_old_missing_but_keeps_newer_work(self):
        now = 1_800_000_000
        self._touch("gone.md", "deleted at the source\n", now - 5000)     # 書庫より前から有る・書庫に無い → 消す
        self._touch("newwork.md", "written after the snapshot\n", now + 5000)  # 書庫のあとに書いた → 守る
        (self.root / "same.md").write_text("hi\n")
        os.utime(self.root / "same.md", (now - 9000, now - 9000))
        stage = self._stage({"same.md": "hi\n", "a.md": "NEW\n"}, mtime=now)
        os.utime(self.root / "a.md", (now - 9000, now - 9000))
        r = ai.apply(str(self.root), str(stage))
        self.assertEqual((self.root / "a.md").read_text(), "NEW\n")
        self.assertFalse((self.root / "gone.md").exists(), "書庫に無い古いファイルは消える")
        self.assertTrue((self.root / "newwork.md").exists(), "書庫のあとの作業は消さない")
        self.assertEqual((Path(r["backup"]) / "gone.md").read_text(), "deleted at the source\n")  # 消したものは退避
        self.assertEqual((r["removed"], r["protected"]), (1, 1), r)

    def test_merge_does_not_delete(self):
        now = 1_800_000_000
        self._touch("gone.md", "x\n", now - 5000)
        stage = self._stage({"a.md": "NEW\n"}, mtime=now)
        os.utime(self.root / "a.md", (now - 9000, now - 9000))
        r = ai.apply(str(self.root), str(stage), merge=True)
        self.assertTrue((self.root / "gone.md").exists())
        self.assertEqual(r["removed"], 0)

    def test_newer_vault_file_is_held_not_overwritten(self):
        now = 1_800_000_000
        self._touch("a.md", "my newer work\n", now + 100)
        stage = self._stage({"a.md": "old record\n"}, mtime=now)
        c = ai.classify(self.root, stage / "v")
        self.assertEqual([h["rel"] for h in c["held"]], ["a.md"], c)
        self.assertIn("古い記録", c["held"][0]["why"][0])
        r = ai.apply(str(self.root), str(stage))
        self.assertEqual((self.root / "a.md").read_text(), "my newer work\n")
        self.assertEqual(r["held"], 1)
        stage2 = self._stage({"a.md": "old record\n"}, mtime=now)
        ai.apply(str(self.root), str(stage2), force=True)
        self.assertEqual((self.root / "a.md").read_text(), "old record\n", "--force では上書きする")

    def test_broken_content_is_held(self):
        now = 1_800_000_000
        good = "---\ntime: 2026-01-01\n---\n\n" + "これは長いノートの本文です。" * 30 + "\n"
        self._touch("n.md", good, now - 100)
        cases = {
            "garbled": ("縺薙ｌ縺ｯ繝弱ｼ繝医〒縺吶" * 12),
            "empty": "",
            "truncated": good[:40],
            "nofront": "これは長いノートの本文です。" * 30 + "\n",
            "fffd": good + "\ufffd\ufffd",
        }
        for name, body in cases.items():
            stage = self._stage({"n.md": body}, mtime=now)
            c = ai.classify(self.root, stage / "v")
            self.assertEqual([h["rel"] for h in c["held"]], ["n.md"], (name, c))
            self.assertEqual(c["changed"], [], name)
        stage = self._stage({"n.md": b"\xff\xfe\x00bad"}, mtime=now)
        self.assertEqual(len(ai.classify(self.root, stage / "v")["held"]), 1, "UTF-8 として読めない")
        # 正常な更新は通る
        stage = self._stage({"n.md": good + "追記\n"}, mtime=now)
        c = ai.classify(self.root, stage / "v")
        self.assertEqual((c["changed"], c["held"]), (["n.md"], []))

    def test_strong_warnings(self):
        now = 1_800_000_000
        for i in range(12):
            self._touch("mine%d.md" % i, "mine\n", now - 1000)
        # 別の vault の書庫（同じパスが 1 つもない）
        stage = self._stage({"other%d.md" % i: "o\n" for i in range(12)}, mtime=now)
        c = ai.classify(self.root, stage / "v")
        self.assertTrue(any("別の vault" in x for x in c["strong"]), c["strong"])
        # 同じ vault の少し進んだ書庫（増えただけ・少し消えただけ）は、警告しない
        files = {"mine%d.md" % i: "mine\n" for i in range(11)}
        files.update({"extra%d.md" % i: "x\n" for i in range(30)})
        stage = self._stage(files, mtime=now)
        c = ai.classify(self.root, stage / "v")
        self.assertEqual(c["strong"], [], c["strong"])
        # 古い書庫（vault の最新より前）
        self._touch("mine0.md", "edited later\n", now + 5000)
        stage = self._stage(files, mtime=now)
        c = ai.classify(self.root, stage / "v")
        self.assertTrue(any("古い記録" in x for x in c["strong"]), c["strong"])

    def test_missing_archive(self):
        self.assertIn("error", ai.plan(str(self.root), str(self.root / "nope.7z"), None))


if __name__ == "__main__":
    unittest.main()
