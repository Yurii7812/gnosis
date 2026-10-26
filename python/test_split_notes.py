#!/usr/bin/env python3
import datetime as dt
import hashlib
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import split_notes as sp

NOW = dt.datetime(2026, 10, 21, 9, 0, 0)
SRC = """---
time: 2026-01-01 00:00:00
title: 大きなノート
---

# 大きなノート

導入。

## 栽培

水やりは控えめに。
[道具](tools.md)を使う。

### 土

水はけを良くする。

## 料理

```
## これは見出しではない
```
焼く。

ParentBranch:
[親](parent.md)
"""


def md5(root):
    return {str(p.relative_to(root)): hashlib.md5(p.read_bytes()).hexdigest() for p in root.rglob("*") if p.is_file()}


class SplitTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(dir=str(Path.home() / "gnosis-work" / "test"))
        self.addCleanup(self.tmp.cleanup)
        r = self.root = Path(self.tmp.name)
        (r / "big.md").write_text(SRC, encoding="utf-8")
        (r / "tools.md").write_text("# 道具\n", encoding="utf-8")
        (r / "parent.md").write_text("# 親\n", encoding="utf-8")
        (r / "ref.md").write_text("# 参照\n\n[栽培の節](big.md#栽培)と[料理](big.md#料理)と[全体](big.md)\n", encoding="utf-8")
        self.before = md5(r)

    def test_split_section_with_subsection(self):
        out = sp.split(self.root, "big.md", "栽培", "cultivation.md", NOW)
        self.assertTrue(out["ok"])
        new = (self.root / "cultivation.md").read_text(encoding="utf-8")
        self.assertTrue(new.startswith("---\ntime: 2026-10-21 09:00:00\ntitle: 栽培\n---\n\n# 栽培\n\n水やりは控えめに。"))
        self.assertIn("### 土\n\n水はけを良くする。", new)                        # 下の階層(###)も一緒に
        self.assertNotIn("料理", new)                                             # 次の同階層(##)の手前まで
        self.assertTrue(new.rstrip().endswith("Related:\n[大きなノート](big.md)"))   # 元ノートへのつながりを記録
        old = (self.root / "big.md").read_text(encoding="utf-8")
        self.assertIn("## 栽培\n\n→ [栽培](cultivation.md)（分割しました）\n", old)   # 見出しは残る
        self.assertNotIn("水やりは控えめに", old)
        self.assertIn("## 料理", old)
        self.assertIn("ParentBranch:\n[親](parent.md)", old)                       # 末尾の関係ブロックは元に残る
        self.assertEqual(out["lines"], 6)                                          # 切り出した行数（空行を除く先頭・末尾を落とした本文）

    def test_inbound_anchor_links_follow_but_others_stay(self):
        out = sp.split(self.root, "big.md", "栽培", "cultivation.md", NOW)
        self.assertEqual(out["relinked"], ["ref.md"])
        ref = (self.root / "ref.md").read_text(encoding="utf-8")
        self.assertIn("[栽培の節](cultivation.md)", ref)
        self.assertIn("[料理](big.md#料理)", ref)                                   # 別の節は元のまま
        self.assertIn("[全体](big.md)", ref)                                       # 元ノートへのリンクは壊れない
        self.assertTrue((self.root / "big.md").exists())

    def test_code_block_hash_is_not_a_heading(self):
        sp.split(self.root, "big.md", "料理", "cooking.md", NOW)
        new = (self.root / "cooking.md").read_text(encoding="utf-8")
        self.assertIn("## これは見出しではない", new)
        self.assertIn("焼く。", new)
        self.assertNotIn("ParentBranch", new.split("Related:")[0])               # 関係ブロックは切り出しに含めない

    def test_refusals_leave_everything_unchanged(self):
        cases = [(("big.md", "ない見出し", "x.md"), "見出しがありません"), (("big.md", "大きなノート", "x.md"), "題"),
                 (("big.md", "栽培", "sub/x.md"), "同じフォルダ"), (("big.md", "栽培", "x.txt"), "同じフォルダ"), (("big.md", "栽培", "tools.md"), "上書きしません"),
                 (("../outside.md", "栽培", "x.md"), "vault の外"), (("big.md", "栽培", ".hidden.md"), "ドット"), (("none.md", "栽培", "x.md"), "ありません")]
        for args, msg in cases:
            with self.assertRaises(ValueError, msg=str(args)) as cm:
                sp.split(self.root, *args, now=NOW)
            self.assertIn(msg, str(cm.exception))
        self.assertEqual(self.before, md5(self.root))                              # 失敗では何も変わらない・控えも作らない

    def test_duplicate_and_empty_headings_refused(self):
        (self.root / "dup.md").write_text("# 題\n\n## A\n\n本文1\n\n## A\n\n本文2\n\n## 空\n\n## 次\n\nx\n", encoding="utf-8")
        with self.assertRaises(ValueError) as cm:
            sp.split(self.root, "dup.md", "A", "a.md", NOW)
        self.assertIn("複数", str(cm.exception))
        with self.assertRaises(ValueError) as cm:
            sp.split(self.root, "dup.md", "空", "e.md", NOW)
        self.assertIn("空", str(cm.exception))

    def test_undo_restores_everything_and_only_once(self):
        sp.split(self.root, "big.md", "栽培", "cultivation.md", NOW)
        self.assertEqual(sp.last(self.root)["created"], ["cultivation.md"])
        r = sp.undo(self.root)
        self.assertTrue(r["ok"])
        after = {k: v for k, v in md5(self.root).items() if not k.startswith(".state/")}
        self.assertEqual({k: v for k, v in self.before.items()}, after)          # ファイルが完全に元通り・新ノートは消える
        self.assertFalse((self.root / "cultivation.md").exists())
        self.assertFalse(sp.undo(self.root)["ok"])                                 # 2 回目は取り消すものがない
        self.assertFalse(sp.last(self.root)["ok"])

    def test_undo_refuses_after_later_edit_unless_forced(self):
        sp.split(self.root, "big.md", "栽培", "cultivation.md", NOW)
        (self.root / "cultivation.md").write_text("手で書き足した\n", encoding="utf-8")
        r = sp.undo(self.root)
        self.assertFalse(r["ok"])
        self.assertEqual(r["changed"], ["cultivation.md"])
        self.assertTrue((self.root / "cultivation.md").exists())                   # 手で書いた内容を勝手に消さない
        self.assertTrue(sp.undo(self.root, force=True)["ok"])
        self.assertFalse((self.root / "cultivation.md").exists())

    def test_cli(self):
        self.assertEqual(sp.main(["split", str(self.root), "big.md", "栽培", "c.md"]), 0)
        self.assertEqual(sp.main(["last", str(self.root)]), 0)
        self.assertEqual(sp.main(["split", str(self.root), "big.md", "栽培", "c.md"]), 1)
        self.assertEqual(sp.main(["undo", str(self.root)]), 0)
        self.assertEqual(sp.main(["undo", str(self.root)]), 1)
        self.assertEqual(sp.main(["bogus"]), 2)


if __name__ == "__main__":
    unittest.main()
