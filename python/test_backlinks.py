#!/usr/bin/env python3
import hashlib
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import backlinks as bk


def note(root, name, title, body="", fzid=""):
    fm = f"---\ntime: 2026-01-01 00:00:00\ntitle: {title}\n" + (f'folgezettel: "{fzid}"\n' if fzid else "") + "---\n\n"
    (root / name).write_text(fm + f"# {title}\n\n" + body + "\n", encoding="utf-8")


class BacklinkTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(dir=str(Path.home() / "Desktop" / "test"))
        self.addCleanup(self.tmp.cleanup)
        r = self.root = Path(self.tmp.name)
        note(r, "target.md", "ハーブ栽培", "本文", "1")
        note(r, "a.md", "本文リンク", "前の行\nここで[ハーブ栽培](target.md)に触れる\n次の行")
        note(r, "b.md", "子", "ParentBranch:\n[ハーブ栽培](target.md)\n\n本文", "1a")
        note(r, "c.md", "文脈", "Context:\n[ハーブ栽培](target.md)\n\n本文")
        note(r, "d.md", "言及だけ", "ハーブ栽培について書いた。リンクはしていない。")
        note(r, "e.md", "コードの中", "```\nハーブ栽培\n```\nリンクの中は [ハーブ栽培とは別](other.md) です")
        note(r, "f.md", "無関係", "なにもない")
        self.before = {p.name: hashlib.md5(p.read_bytes()).hexdigest() for p in r.glob("*.md")}

    def test_backlinks_with_kinds_and_preview(self):
        r = bk.backlinks(self.root, "target.md")
        by = {x["path"]: x for x in r["backlinks"]}
        self.assertEqual(set(by), {"a.md", "b.md", "c.md"})
        self.assertEqual(by["a.md"]["kinds"], ["link"])
        self.assertEqual(by["b.md"]["kinds"], ["parent_branch"])
        self.assertIn("ParentBranch", by["b.md"]["kind_labels"][0])
        self.assertEqual(by["c.md"]["kinds"], ["context"])
        pv = by["a.md"]["preview"]
        self.assertEqual(pv["line"], 9)                                         # ファイルの実際の行
        self.assertIn("ここで[ハーブ栽培](target.md)に触れる", pv["text"])
        self.assertEqual(pv["before"], ["前の行"])
        self.assertEqual(pv["after"], ["次の行"])
        self.assertEqual(by["b.md"]["fz"], "1a")
        self.assertEqual(r["count"], 3)
        # 題・ファイル名どちらでも引ける
        self.assertEqual(bk.backlinks(self.root, "ハーブ栽培")["count"], 3)
        self.assertEqual(bk.backlinks(self.root, "target")["count"], 3)
        with self.assertRaises(ValueError):
            bk.backlinks(self.root, "nothing")

    def test_unlinked_mentions_are_text_matches_only(self):
        u = bk.unlinked(self.root, "target.md")
        paths = [x["path"] for x in u["unlinked"]]
        self.assertEqual(paths, ["d.md"])                                       # リンク済み・コードの中・リンクの文字の中は数えない
        self.assertEqual(u["unlinked"][0]["line"], 8)
        self.assertEqual(bk.unlinked(self.root, "f.md")["count"], 0)
        note(self.root, "tiny.md", "星", "星を見る")                              # 短すぎる題（2 文字未満）は照合しない
        self.assertEqual(bk.unlinked(self.root, "tiny.md")["unlinked"], [])

    def test_markdown_and_cli_and_read_only(self):
        md = bk.to_md(bk.backlinks(self.root, "target.md"), bk.unlinked(self.root, "target.md"))
        self.assertIn("# バックリンク: ハーブ栽培", md)
        self.assertIn("(a.md)", md)
        self.assertIn("# 未リンクの言及（文字の一致）: 1 件", md)
        for args in ([str(self.root), "target.md"], [str(self.root), "target.md", "--unlinked"], [str(self.root), "target.md", "--md"]):
            self.assertEqual(bk.main(args), 0)
        self.assertEqual(bk.main([str(self.root), "zzz"]), 1)
        self.assertEqual(bk.main(["x"]), 2)
        self.assertEqual(self.before, {p.name: hashlib.md5(p.read_bytes()).hexdigest() for p in self.root.glob("*.md")})


if __name__ == "__main__":
    unittest.main()
