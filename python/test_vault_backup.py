#!/usr/bin/env python3
import datetime as dt
import hashlib
import json
import os
import sys
import tarfile
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import vault_backup as vb

NOW = dt.datetime(2026, 10, 20, 22, 30, 0)


class BackupTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(dir=str(Path.home() / "Desktop" / "test"))
        self.addCleanup(self.tmp.cleanup)
        base = Path(self.tmp.name)
        self.root = base / "vault"
        self.out = base / "backups"
        self.root.mkdir()
        r = self.root
        (r / "a.md").write_text("# A\n\n本文\n", encoding="utf-8")
        (r / "sub").mkdir()
        (r / "sub" / "b.md").write_text("# B\n", encoding="utf-8")
        (r / "pic.png").write_bytes(b"\x89PNG" + bytes(range(256)) * 10)
        (r / ".gnosis").mkdir()
        (r / ".gnosis" / "cache.sqlite").write_bytes(b"cache")
        (r / ".crypt").mkdir()
        (r / ".crypt" / "x").write_bytes(b"secret-cipher")
        (r / ".hidden.md").write_text("hidden", encoding="utf-8")
        os.symlink(base / "outside.txt", r / "link.md")
        (base / "outside.txt").write_text("OUTSIDE", encoding="utf-8")
        self.before = self.snapshot()

    def snapshot(self):
        return {p.relative_to(self.root).as_posix(): hashlib.md5(p.read_bytes()).hexdigest()
                for p in self.root.rglob("*") if p.is_file() and not p.is_symlink()}

    def test_backup_contents_and_verify(self):
        r = vb.backup(self.root, self.out, now=NOW)
        self.assertTrue(r["verified"])
        self.assertEqual(Path(r["archive"]).name, "20261020223000-vault.tar.gz")
        with tarfile.open(r["archive"]) as tar:
            names = sorted(tar.getnames())
        self.assertEqual(names, ["a.md", "pic.png", "sub/b.md"])            # ドット始まり・暗号箱・キャッシュ・リンクは入らない
        m = json.loads(Path(r["manifest"]).read_text(encoding="utf-8"))
        self.assertEqual(m["version"], 1)
        self.assertEqual({e["path"] for e in m["files"]}, set(names))
        self.assertEqual(self.before, self.snapshot())                       # 元の vault は無変更
        self.assertEqual(vb.verify(r["archive"]), {"ok": True, "files": 3, "problems": []})
        self.assertEqual(sorted(p.name for p in self.out.iterdir()), ["20261020223000-vault.manifest.json", "20261020223000-vault.tar.gz"])

    def test_refuses_overwrite_and_inside_output(self):
        vb.backup(self.root, self.out, now=NOW)
        with self.assertRaises(ValueError):
            vb.backup(self.root, self.out, now=NOW)                          # 同じ名前には上書きしない
        with self.assertRaises(ValueError):
            vb.backup(self.root, self.root / "backups", now=NOW)             # vault の中には出さない
        with self.assertRaises(ValueError):
            vb.backup(self.root, self.root, now=NOW)
        self.assertFalse((self.root / "backups").exists())

    def test_detects_corruption_and_never_calls_it_success(self):
        r = vb.backup(self.root, self.out, now=NOW)
        arc = Path(r["archive"])
        # 1. manifest がない
        mp = Path(r["manifest"])
        saved = mp.read_text(encoding="utf-8")
        mp.unlink()
        self.assertFalse(vb.verify(arc)["ok"])
        mp.write_text("{壊れた", encoding="utf-8")
        self.assertFalse(vb.verify(arc)["ok"])
        # 2. manifest のハッシュが違う（中身が書き換わった想定）
        m = json.loads(saved)
        m["files"][0]["sha256"] = "0" * 64
        mp.write_text(json.dumps(m), encoding="utf-8")
        v = vb.verify(arc)
        self.assertFalse(v["ok"])
        self.assertEqual(v["problems"][0]["path"], m["files"][0]["path"])
        # 3. manifest にあるファイルがアーカイブに無い
        m = json.loads(saved)
        m["files"].append({"path": "ghost.md", "size": 1, "sha256": "a" * 64})
        mp.write_text(json.dumps(m), encoding="utf-8")
        self.assertIn("ghost.md", [p["path"] for p in vb.verify(arc)["problems"]])
        mp.write_text(saved, encoding="utf-8")
        self.assertTrue(vb.verify(arc)["ok"])
        # 4. アーカイブ自体が壊れている（途中で切れた）
        data = arc.read_bytes()
        arc.write_bytes(data[: len(data) // 2])
        self.assertFalse(vb.verify(arc)["ok"])
        # 5. 壊れたバックアップは復元しない
        with self.assertRaises(ValueError):
            vb.restore(arc, self.out.parent / "restored")
        self.assertFalse((self.out.parent / "restored").exists())

    def test_restore_only_into_new_or_empty_dir(self):
        r = vb.backup(self.root, self.out, now=NOW)
        dest = self.out.parent / "restored"
        res = vb.restore(r["archive"], dest)
        self.assertEqual((res["restored"], res["verified"]), (3, True))
        for rel in ("a.md", "sub/b.md", "pic.png"):
            self.assertEqual((dest / rel).read_bytes(), (self.root / rel).read_bytes())
        # 空のフォルダにはよい。中身のあるフォルダには何もしない
        empty = self.out.parent / "empty"
        empty.mkdir()
        vb.restore(r["archive"], empty)
        self.assertTrue((empty / "a.md").exists())
        busy = self.out.parent / "busy"
        busy.mkdir()
        (busy / "mine.txt").write_text("大事", encoding="utf-8")
        with self.assertRaises(ValueError):
            vb.restore(r["archive"], busy)
        self.assertEqual([p.name for p in busy.iterdir()], ["mine.txt"])
        with self.assertRaises(ValueError):
            vb.restore(r["archive"], self.root)                               # 元の vault へは書き戻さない
        self.assertEqual(self.before, self.snapshot())

    def test_large_files_are_skipped_and_reported(self):
        (self.root / "big.bin").write_bytes(b"x" * (2 * 1024 * 1024))
        r = vb.backup(self.root, self.out, max_mb=1, now=NOW)
        self.assertEqual([s["path"] for s in r["skipped_large"]], ["big.bin"])
        with tarfile.open(r["archive"]) as tar:
            self.assertNotIn("big.bin", tar.getnames())
        res = vb.restore(r["archive"], self.out.parent / "restored")
        self.assertEqual([s["path"] for s in res["skipped_large"]], ["big.bin"])   # 復元でも「入っていない」ことを伝える

    def test_dangerous_paths_in_archive_are_rejected(self):
        r = vb.backup(self.root, self.out, now=NOW)
        arc = Path(r["archive"])
        evil = self.out / "20261020223001-evil.tar.gz"
        with tarfile.open(evil, "w:gz") as tar:
            import io
            info = tarfile.TarInfo("../escape.txt")
            info.size = 3
            tar.addfile(info, io.BytesIO(b"bad"))
        (self.out / "20261020223001-evil.manifest.json").write_text(json.dumps({"version": 1, "files": []}), encoding="utf-8")
        v = vb.verify(evil)
        self.assertFalse(v["ok"])
        with self.assertRaises(ValueError):
            vb.restore(evil, self.out.parent / "r2")
        self.assertFalse((self.out.parent / "escape.txt").exists())

    def test_list_and_cli(self):
        vb.backup(self.root, self.out, now=NOW)
        lst = vb.list_backups(self.out)
        self.assertEqual((lst[0]["vault"], lst[0]["files"], lst[0]["manifest"]), ("vault", 3, True))
        self.assertEqual(vb.main([str(self.root), "backup", str(self.out)]), 0)
        self.assertEqual(vb.main(["verify", str(self.out / "nope.tar.gz")]), 1)
        self.assertEqual(vb.main(["bogus"]), 2)


if __name__ == "__main__":
    unittest.main()
