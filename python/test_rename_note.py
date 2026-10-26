#!/usr/bin/env python3
import hashlib
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import rename_note as rn


def md5(root):
    return {str(p.relative_to(root)): hashlib.md5(p.read_bytes()).hexdigest() for p in root.rglob("*") if p.is_file()}


class RenameTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(dir=str(Path.home() / "gnosis-work" / "test"))
        self.addCleanup(self.tmp.cleanup)
        r = self.root = Path(self.tmp.name)
        (r / "sub").mkdir()
        (r / "old name.md").write_text("# 旧\n\n[自分](old%20name.md)\n[兄弟](sub/other.md)\n![図](img/p.png)\n\n```\n[コード](old%20name.md)\n```\n", encoding="utf-8")
        (r / "a.md").write_text("# A\n\n[旧](old%20name.md)と[節](old%20name.md#見出し)と[題つき](old%20name.md \"タイトル\")\n[外](https://x.example/old%20name.md)と[アンカーのみ](#x)\n```\n[コード](old%20name.md)\n```\n", encoding="utf-8")
        (r / "sub" / "other.md").write_text("# O\n\n[旧](../old%20name.md)\n[無関係](../a.md)\n", encoding="utf-8")
        (r / "raw.md").write_text("# R\n\n[生の日本語](旧メモ.md)\n", encoding="utf-8")
        (r / "旧メモ.md").write_text("# 旧メモ\n", encoding="utf-8")
        (r / "img").mkdir()
        (r / "img" / "p.png").write_bytes(b"png")
        self.before = md5(r)

    def test_dry_run_changes_nothing(self):
        r = rn.rename(self.root, "old name.md", "new.md", dry_run=True)
        self.assertTrue(r["dry_run"])
        self.assertEqual(r["links_updated"], 5)                              # a.md 3 + sub/other.md 1 + 自分自身 1
        self.assertEqual(self.before, md5(self.root))
        self.assertNotIn("undo", r)

    def test_rename_in_same_folder_updates_all_references(self):
        r = rn.rename(self.root, "old name.md", "new name.md")
        self.assertFalse((self.root / "old name.md").exists())
        self.assertTrue((self.root / "new name.md").exists())
        a = (self.root / "a.md").read_text(encoding="utf-8")
        self.assertIn("[旧](new%20name.md)", a)                              # %20 の書き方を保つ
        self.assertIn("[節](new%20name.md#見出し)", a)                        # アンカーを保つ
        self.assertIn('[題つき](new%20name.md "タイトル")', a)                  # タイトル属性を保つ
        self.assertIn("[外](https://x.example/old%20name.md)", a)             # URL は触らない
        self.assertIn("[アンカーのみ](#x)", a)
        self.assertIn("```\n[コード](old%20name.md)\n```", a)                  # コードブロックは触らない
        self.assertIn("[旧](../new%20name.md)", (self.root / "sub" / "other.md").read_text(encoding="utf-8"))   # 別フォルダからの相対
        self.assertIn("[無関係](../a.md)", (self.root / "sub" / "other.md").read_text(encoding="utf-8"))
        moved = (self.root / "new name.md").read_text(encoding="utf-8")
        self.assertIn("[自分](new%20name.md)", moved)
        self.assertIn("[兄弟](sub/other.md)", moved)                          # 同じフォルダなので他のリンクは不変
        self.assertEqual(r["links_updated"], 5)
        self.assertIn("(旧メモ.md)", (self.root / "raw.md").read_text(encoding="utf-8"))
        self.assertEqual(md5(self.root)["raw.md"], self.before["raw.md"])    # 関係ないノートは 1 バイトも変わらない

    def test_raw_japanese_names_stay_raw(self):
        rn.rename(self.root, "旧メモ.md", "新メモ.md")
        self.assertIn("[生の日本語](新メモ.md)", (self.root / "raw.md").read_text(encoding="utf-8"))

    def test_move_to_other_folder_recomputes_own_links(self):
        rn.rename(self.root, "old name.md", "sub/deep/moved.md")
        moved = (self.root / "sub" / "deep" / "moved.md").read_text(encoding="utf-8")
        self.assertIn("[自分](moved.md)", moved)
        self.assertIn("[兄弟](../other.md)", moved)                           # 移した先から計算し直す
        self.assertIn("![図](../../img/p.png)", moved)                        # 画像も
        self.assertIn("[コード](old%20name.md)", moved)                       # コードの中は触らない
        self.assertIn("[旧](sub/deep/moved.md)", (self.root / "a.md").read_text(encoding="utf-8"))
        self.assertIn("[旧](deep/moved.md)", (self.root / "sub" / "other.md").read_text(encoding="utf-8"))

    def test_undo_restores_exactly_and_only_once(self):
        rn.rename(self.root, "old name.md", "sub/deep/moved.md")
        self.assertEqual(rn.last(self.root)["new"], "sub/deep/moved.md")
        u = rn.undo(self.root)
        self.assertTrue(u["ok"])
        after = {k: v for k, v in md5(self.root).items() if not k.startswith(".state/")}
        self.assertEqual(after, self.before)                                  # 完全に元通り（新しい場所は消える）
        self.assertFalse((self.root / "sub" / "deep" / "moved.md").exists())
        self.assertFalse(rn.undo(self.root)["ok"])

    def test_undo_refuses_after_later_edit_unless_forced(self):
        rn.rename(self.root, "old name.md", "new.md")
        (self.root / "a.md").write_text("# 手で直した\n", encoding="utf-8")
        r = rn.undo(self.root)
        self.assertFalse(r["ok"])
        self.assertEqual(r["changed"], ["a.md"])
        self.assertTrue((self.root / "new.md").exists())                       # 失敗では何も戻さない
        self.assertTrue(rn.undo(self.root, force=True)["ok"])
        self.assertTrue((self.root / "old name.md").exists())

    def test_refusals_change_nothing(self):
        cases = [(("old name.md", "a.md"), "上書きしません"), (("old name.md", "old name.md"), "同じ"), (("old name.md", "x.txt"), ".md"),
                 (("old name.md", "../out.md"), "vault の外"), (("old name.md", ".state/x.md"), "ドット"), (("nothing.md", "x.md"), "ありません"), (("img/p.png", "x.md"), "ありません")]
        for args, msg in cases:
            with self.assertRaises(ValueError, msg=str(args)) as cm:
                rn.rename(self.root, *args)
            self.assertIn(msg, str(cm.exception))
        self.assertEqual(self.before, md5(self.root))

    def test_capture_state_follows(self):
        (self.root / ".state").mkdir()
        (self.root / ".state" / "capture_imported.json").write_text(json.dumps({"ids": {"c1": "old name.md", "c2": "old name.md#sec", "c3": "a.md"}, "entries": {}}), encoding="utf-8")
        r = rn.rename(self.root, "old name.md", "moved.md")
        self.assertEqual(r["capture_ids"], 2)
        st = json.loads((self.root / ".state" / "capture_imported.json").read_text(encoding="utf-8"))
        self.assertEqual(st["ids"], {"c1": "moved.md", "c2": "moved.md#sec", "c3": "a.md"})
        rn.undo(self.root)
        st = json.loads((self.root / ".state" / "capture_imported.json").read_text(encoding="utf-8"))
        self.assertEqual(st["ids"]["c1"], "old name.md")                       # 取り消しで記録も戻る

    def test_broken_capture_state_is_left_alone(self):
        (self.root / ".state").mkdir()
        (self.root / ".state" / "capture_imported.json").write_text("{broken", encoding="utf-8")
        rn.rename(self.root, "old name.md", "moved.md")
        self.assertEqual((self.root / ".state" / "capture_imported.json").read_text(encoding="utf-8"), "{broken")

    def test_cli(self):
        self.assertEqual(rn.main(["rename", str(self.root), "old name.md", "n.md", "--dry-run"]), 0)
        self.assertTrue((self.root / "old name.md").exists())
        self.assertEqual(rn.main(["rename", str(self.root), "old name.md", "n.md"]), 0)
        self.assertEqual(rn.main(["last", str(self.root)]), 0)
        self.assertEqual(rn.main(["rename", str(self.root), "old name.md", "n.md"]), 1)
        self.assertEqual(rn.main(["undo", str(self.root)]), 0)
        self.assertEqual(rn.main(["undo", str(self.root)]), 1)
        self.assertEqual(rn.main(["bogus"]), 2)


if __name__ == "__main__":
    unittest.main()
