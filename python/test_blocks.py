#!/usr/bin/env python3
import contextlib
import hashlib
import io
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import blocks as bk

NOTE = """---
time: 2026-01-01 00:00:00
title: 元
---

# 元

導入の段落。
続きの行。 ^intro

## 栽培

水やりは控えめに。

土は乾燥気味に。 ^soil

### 土の詳細

水はけを良くする。

## 料理

```
## コード内の見出し
段落 ^code
```
焼く。

ParentBranch:
[親](parent.md)
"""


class BlocksTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(dir=str(Path.home() / "Desktop" / "test"))
        self.addCleanup(self.tmp.cleanup)
        r = self.root = Path(self.tmp.name)
        (r / "src.md").write_text(NOTE, encoding="utf-8")
        (r / "ref.md").write_text("# 参照\n\n[節](src.md#栽培)と[ブロック](src.md#^soil)と[URL形式](src.md#%E6%A0%BD%E5%9F%B9)\n[切れ見出し](src.md#存在しない)と[切れブロック](src.md#^nope)\n[別ファイル欠落](missing.md#x)と[外](https://e.com/a.md#x)\n```\n[コード内](src.md#無い)\n```\n", encoding="utf-8")
        self.before = {p.name: hashlib.md5(p.read_bytes()).hexdigest() for p in r.glob("*.md")}

    def lines(self):
        return NOTE.split("\n")

    def ln(self, text):
        """NOTE の中で text を含む最初の行の番号（1 から）。数字を決め打ちしない。"""
        return next(i for i, x in enumerate(NOTE.split("\n"), 1) if text in x)

    def test_heading_section_extent_and_relation_block(self):
        self.assertEqual(bk.resolve(self.lines(), "栽培"), ["水やりは控えめに。", "", "土は乾燥気味に。 ^soil", "", "### 土の詳細", "", "水はけを良くする。"])   # 下の階層も含む
        self.assertEqual(bk.resolve(self.lines(), "土の詳細"), ["水はけを良くする。"])
        cooking = bk.resolve(self.lines(), "料理")
        self.assertEqual(cooking[-1], "焼く。")                                    # 末尾の ParentBranch ブロックは含めない
        self.assertIn("## コード内の見出し", cooking)                              # コードブロック内は見出しではない
        self.assertIsNone(bk.resolve(self.lines(), "存在しない"))

    def test_anchor_spellings(self):
        for a in ("栽培", "%E6%A0%BD%E5%9F%B9"):
            self.assertIsNotNone(bk.resolve(self.lines(), a), a)
        self.assertEqual(bk.resolve(["# T", "", "## My Heading", "", "x"], "my-heading"), ["x"])      # 小文字ハイフン形式

    def test_block_by_id_strips_marker(self):
        self.assertEqual(bk.resolve(self.lines(), "^intro"), ["導入の段落。", "続きの行。"])        # 複数行の段落・印は外す
        self.assertEqual(bk.resolve(self.lines(), "^soil"), ["土は乾燥気味に。"])
        self.assertIsNone(bk.resolve(self.lines(), "^code"))                      # コードブロックの中の ^id は ID ではない
        self.assertEqual([i["id"] for i in bk.ids(self.lines())], ["intro", "soil"])

    def test_block_id_survives_moving_the_paragraph(self):
        moved = "# 元\n\n## 別の節\n\n追加の文。\n\n土は乾燥気味に。 ^soil\n".split("\n")
        self.assertEqual(bk.resolve(moved, "^soil"), ["土は乾燥気味に。"])         # 段落が別の場所に動いても同じ ID で指せる

    def test_add_id_appends_only_and_is_idempotent(self):
        r = bk.add_id(self.root, "src.md", self.ln("水やりは控えめに。"))
        self.assertTrue(r["added"])
        text = (self.root / "src.md").read_text(encoding="utf-8")
        self.assertIn(f"水やりは控えめに。 ^{r['id']}\n", text)
        self.assertEqual(len(text.split("\n")), len(NOTE.split("\n")))            # 行数は増えない(末尾に足すだけ)
        self.assertEqual(text.replace(f" ^{r['id']}", "", 1), NOTE)               # ほかは 1 文字も変わらない
        again = bk.add_id(self.root, "src.md", self.ln("水やりは控えめに。"))
        self.assertFalse(again["added"])
        self.assertEqual(again["id"], r["id"])
        self.assertEqual((self.root / "src.md").read_text(encoding="utf-8"), text)
        self.assertEqual(bk.resolve(text.split("\n"), "^" + r["id"]), ["水やりは控えめに。"])

    def test_add_id_with_explicit_id_and_refusals(self):
        r = bk.add_id(self.root, "src.md", self.ln("続きの行。"), "my-point")
        self.assertEqual(r["id"], "intro")                                        # すでに ID がある段落には付け足さない
        r = bk.add_id(self.root, "src.md", self.ln("水やりは控えめに。"), "key-1")
        self.assertEqual(r["link"], "src.md#^key-1")
        blank = self.ln("水やりは控えめに。") + 1
        code = self.ln("段落 ^code")
        para = self.ln("水はけを良くする。")                                        # まだ ID の無い段落
        for line, bid, msg in ((1, None, "段落の中ではありません"), (blank, None, "段落の中ではありません"), (code, None, "段落の中ではありません"), (para, "intro", "使われています"), (para, "bad id", "英数字")):
            with self.assertRaises(ValueError, msg=str((line, bid))) as cm:
                bk.add_id(self.root, "src.md", line, bid)
            self.assertIn(msg, str(cm.exception))
        with self.assertRaises(ValueError):
            bk.add_id(self.root, "nothing.md", 1)

    def test_check_finds_broken_heading_and_block_links(self):
        r = bk.check(self.root)
        got = {(b["file"], b["anchor"], b["kind"]) for b in r["broken"]}
        self.assertEqual(got, {("ref.md", "存在しない", "見出し"), ("ref.md", "^nope", "ブロック")})   # 正しいもの・コード内・URL・欠落ファイルは指摘しない
        self.assertEqual(r["checked"], 6)                                          # .md を指す #付きリンク（欠落ファイルへのものも数える。URL・コード内は数えない）
        # 見出しの名前を変えると切れる → check が拾う。ブロック ID なら切れない
        (self.root / "src.md").write_text(NOTE.replace("## 栽培", "## 育て方"), encoding="utf-8")
        got2 = {(b["anchor"]) for b in bk.check(self.root)["broken"]}
        self.assertIn("栽培", got2)
        self.assertIn("%E6%A0%BD%E5%9F%B9", got2)
        self.assertNotIn("^soil", got2)

    def test_check_does_not_modify(self):
        bk.check(self.root)
        self.assertEqual(self.before, {p.name: hashlib.md5(p.read_bytes()).hexdigest() for p in self.root.glob("*.md")})

    def test_cli(self):
        def run(*a):
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                rc = bk.main([str(self.root), *a])
            return rc, buf.getvalue()
        self.assertIn("- ^intro", run("ids", "src.md", "--md")[1])
        self.assertIn("壊れているもの 2 件", run("check", "--md")[1])
        self.assertIn("水はけを良くする。", run("show", "src.md", "土の詳細", "--md")[1])
        self.assertEqual(run("add-id", "src.md", str(self.ln("水やりは控えめに。")))[0], 0)
        self.assertEqual(run("show", "src.md", "nope")[0], 1)
        self.assertEqual(run("bogus")[0], 2)


if __name__ == "__main__":
    unittest.main()
