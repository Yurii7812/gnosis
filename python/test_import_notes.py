#!/usr/bin/env python3
import contextlib
import hashlib
import io
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import import_notes as im

PNG = bytes.fromhex("89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c4890000000d49444154789c6360000002000001e221bc330000000049454e44ae426082")


def md5(root):
    return {str(p.relative_to(root)): hashlib.md5(p.read_bytes()).hexdigest() for p in root.rglob("*") if p.is_file()}


class ImportTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(dir=str(Path.home() / "Desktop" / "test"))
        self.addCleanup(self.tmp.cleanup)
        base = Path(self.tmp.name)
        self.root, self.src = base / "vault", base / "obsidian"
        self.root.mkdir(); self.src.mkdir()
        s = self.src
        (s / "assets").mkdir(); (s / "sub").mkdir(); (s / ".obsidian").mkdir(); (s / "a").mkdir(); (s / "b").mkdir()
        (s / "a" / "Twin.md").write_text("a の Twin\n", encoding="utf-8")
        (s / "b" / "Twin.md").write_text("b の Twin\n", encoding="utf-8")
        (s / "assets" / "pic.png").write_bytes(PNG)
        (s / ".obsidian" / "config.json").write_text("{}", encoding="utf-8")
        (s / ".hidden.md").write_text("hidden", encoding="utf-8")
        (s / "Home.md").write_text("# Home\n\n[[Herb]] と [[herb#Care|世話]] と [[Missing Note]] と [[Sub Note]] と [[Twin]]\n![[pic.png]] と ![[pic.png|300]] と ![[Herb]]\n\n```\n[[in code]]\n```\n", encoding="utf-8")
        (s / "Herb.md").write_text("---\ntags: [a]\n---\n\n# Herb\n\n## Care\n\n[[Home]] へ戻る。同名: [[Dup]]\n", encoding="utf-8")
        (s / "sub" / "Sub Note.md").write_text("[[Home]] と [[Dup]] と ![[assets/pic.png]]\r\n", encoding="utf-8")
        (s / "sub" / "Dup.md").write_text("sub の Dup\n", encoding="utf-8")
        (s / "Dup.md").write_text("top の Dup\n", encoding="utf-8")
        (s / "bad.md").write_bytes(b"\xff\xfe bad bytes")
        os.symlink(base / "outside.md", s / "link.md")
        (base / "outside.md").write_text("OUTSIDE", encoding="utf-8")
        self.src_before = md5(self.src)
        self.root_before = md5(self.root)

    def test_plan_changes_nothing_and_reports(self):
        p = im.plan(self.root, self.src, "取り込み/obs")
        self.assertEqual((p["notes"], p["files"]), (7, 1))                                         # Home Herb Sub Note Dup(2) Twin(2) = 7。bad.md は別枠
        self.assertEqual([x["src"] for x in p["skipped"]], ["bad.md"])
        self.assertIn("UTF-8", p["skipped"][0]["reason"])
        self.assertEqual({u["link"] for u in p["unresolved"]}, {"[[Missing Note]]"})
        self.assertEqual([(a["from"], a["name"], a["chosen"]) for a in p["ambiguous"]], [("Home.md", "Twin", "a/Twin.md")])   # 同じフォルダに無い同名だけ曖昧(最短・辞書順を選ぶ)
        self.assertEqual(p["ambiguous"][0]["others"], ["b/Twin.md"])
        self.assertTrue(p["dry_run"])
        self.assertEqual(self.root_before, md5(self.root))
        self.assertEqual(self.src_before, md5(self.src))

    def test_run_converts_links_and_adds_front_matter(self):
        r = im.run(self.root, self.src, "取り込み/obs")
        self.assertTrue(r["finished"])
        out = self.root / "取り込み" / "obs"
        home = (out / "Home.md").read_text(encoding="utf-8")
        self.assertTrue(home.startswith("---\ntime: "))
        self.assertIn("title: Home\n---", home)
        self.assertIn("[Herb](Herb.md)", home)
        self.assertIn("[世話](Herb.md#Care)", home)                                                # 別名と見出しを保つ
        self.assertIn("[Sub Note](sub/Sub%20Note.md)", home)                                       # 空白は %20・サブフォルダは相対
        self.assertIn("Missing Note", home)
        self.assertNotIn("[[Missing Note]]", home)                                                 # 見つからないものは文字だけ(壊れたリンクを作らない)
        self.assertIn("![pic](assets/pic.png)", home)
        self.assertEqual(home.count("![pic](assets/pic.png)"), 2)                                  # |300 のようなサイズ指定は表示名にしない
        self.assertIn("{{include: Herb.md}}", home)                                                # ノートの埋め込みは取り込み表示へ
        self.assertIn("[[in code]]", home)                                                         # コードの中は変換しない
        herb = (out / "Herb.md").read_text(encoding="utf-8")
        self.assertTrue(herb.startswith("---\ntime: "))
        self.assertIn("tags: [a]", herb)                                                           # 既存の front matter は残す
        self.assertIn("title: Herb", herb)
        self.assertIn("[Home](Home.md)", herb)
        self.assertIn("[Dup](Dup.md)", herb)                                                       # 同じフォルダの Dup を選ぶ
        sub = (out / "sub" / "Sub Note.md").read_text(encoding="utf-8")
        self.assertIn("[Home](../Home.md)", sub)                                                   # サブフォルダからは ../
        self.assertIn("[Dup](Dup.md)", sub)                                                        # 同じフォルダを優先
        self.assertIn("![pic](../assets/pic.png)", sub)
        self.assertNotIn("\r", sub)                                                                # CRLF は LF に揃う
        self.assertEqual((out / "assets" / "pic.png").read_bytes(), PNG)
        names = {str(p.relative_to(out)) for p in out.rglob("*") if p.is_file()}
        self.assertFalse(any(n.startswith(".") or "hidden" in n or "link" in n or n == "bad.md" for n in names))   # ドット始まり・リンク・読めないものは取り込まない
        self.assertEqual(self.src_before, md5(self.src))                                           # 取り込み元は不変

    def test_refusals(self):
        (self.root / "exists").mkdir()
        cases = [(("exists",), "すでにあります"), (("../out",), "vault の外"), ((".state/x",), "ドット"), (("",), "サブフォルダ")]
        for args, msg in cases:
            with self.assertRaises(ValueError, msg=str(args)) as cm:
                im.run(self.root, self.src, *args)
            self.assertIn(msg, str(cm.exception))
        with self.assertRaises(ValueError):
            im.run(self.root, self.root / "x", "new")                                              # 取り込み元が無い
        with self.assertRaises(ValueError) as cm:
            im.run(self.root, self.root, "new")                                                    # 重なる
        self.assertIn("重なって", str(cm.exception))
        self.assertFalse((self.root / "new").exists())                                             # 失敗では何も作らない

    def test_interrupt_and_resume_does_not_redo_or_lose(self):
        r = im.run(self.root, self.src, "imp", stop_after=2)
        self.assertFalse(r["finished"])
        self.assertEqual(r["done"], 2)
        out = self.root / "imp"
        written = sorted(str(p.relative_to(out)) for p in out.rglob("*") if p.is_file())
        self.assertEqual(len(written), 2)
        before = {k: v for k, v in md5(out).items()}
        res = im.resume(self.root, r["id"])
        self.assertTrue(res["finished"])
        self.assertEqual(res["done"], 8)                                                           # ノート 7 + 添付 1
        after = md5(out)
        for k, v in before.items():
            self.assertEqual(after[k], v)                                                          # 書き終えたものは書き直さない
        self.assertTrue(im.verify(self.root, r["id"])["ok"])
        # 完了後の resume は何もしない
        again = im.resume(self.root, r["id"])
        self.assertEqual((again["done"], again["pending"]), (8, 0))

    def test_resume_refuses_when_source_changed(self):
        r = im.run(self.root, self.src, "imp", stop_after=1)
        (self.src / "Home.md").write_text("書き換えた\n", encoding="utf-8")
        (self.src / "Herb.md").write_text("書き換えた\n", encoding="utf-8")
        (self.src / "Dup.md").write_text("書き換えた\n", encoding="utf-8")
        res = im.resume(self.root, r["id"])
        self.assertGreaterEqual(res["failed"], 1)
        j = json.loads((self.root / ".state" / "import" / f"{r['id']}.json").read_text(encoding="utf-8"))
        reasons = {i["reason"] for i in j["items"] if i["status"] == "failed"}
        self.assertTrue(any("取り込み元が変わった" in x for x in reasons))                           # 続けられないものは失敗と記録し、内容を混ぜない

    def test_verify_detects_tampering_and_missing_and_broken_links(self):
        r = im.run(self.root, self.src, "imp")
        v = im.verify(self.root, r["id"])
        self.assertTrue(v["ok"])
        self.assertEqual(v["broken_links"], [])                                                      # 取り込み直後は、壊れたリンクが無い
        out = self.root / "imp"
        (out / "Herb.md").write_text("書き換え\n", encoding="utf-8")
        (out / "Home.md").unlink()
        v2 = im.verify(self.root, r["id"])
        self.assertFalse(v2["ok"])
        self.assertEqual(v2["changed"], ["imp/Herb.md"])
        self.assertEqual(v2["missing"], ["imp/Home.md"])
        self.assertTrue(any(b["file"] == "imp/sub/Sub Note.md" and b["target"] == "../Home.md" for b in v2["broken_links"]))   # 消えた Home.md を指すリンクが壊れたと分かる

    def test_broken_links_counted(self):
        r = im.run(self.root, self.src, "imp")
        (self.root / "imp" / "Herb.md").unlink()                                                   # 取り込んだノートが消えると、それを指すリンクが壊れる
        v = im.verify(self.root, r["id"])
        self.assertTrue(any(b["target"] == "Herb.md" or b["target"].startswith("Herb.md#") for b in v["broken_links"]))
        self.assertEqual(v["missing"], ["imp/Herb.md"])

    def test_undo_removes_only_unchanged_files(self):
        r = im.run(self.root, self.src, "imp")
        (self.root / "imp" / "Home.md").write_text("手で直した\n", encoding="utf-8")
        u = im.undo(self.root, r["id"])
        self.assertEqual(u["kept_modified"], ["imp/Home.md"])                                      # 変更されたものは残す
        self.assertEqual(u["removed"], 7)
        self.assertEqual((self.root / "imp" / "Home.md").read_text(encoding="utf-8"), "手で直した\n")
        self.assertFalse((self.root / "imp" / "assets").exists())                                  # 空になったフォルダは片づく
        r2 = im.run(self.root, self.src, "imp2")
        self.assertEqual(im.undo(self.root, r2["id"])["kept_modified"], [])
        self.assertFalse((self.root / "imp2").exists())
        self.assertEqual(md5(self.src), self.src_before)

    def test_existing_vault_files_are_never_touched(self):
        (self.root / "keep.md").write_text("# 既存\n", encoding="utf-8")
        before = md5(self.root)
        r = im.run(self.root, self.src, "imp")
        im.verify(self.root, r["id"]); im.undo(self.root, r["id"])
        self.assertEqual({k: v for k, v in md5(self.root).items() if not k.startswith(".state")}, {k: v for k, v in before.items()})

    def test_bad_ids(self):
        for bad in ("../x", "zzz", "", "0123456789ab"):
            with self.assertRaises(ValueError):
                im.verify(self.root, bad)

    def test_cli(self):
        def run(*a):
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                rc = im.main(list(a))
            return rc, buf.getvalue()
        rc, out = run("plan", str(self.root), str(self.src), "c")
        self.assertEqual(rc, 0)
        self.assertEqual(self.root_before, md5(self.root))
        rc, out = run("run", str(self.root), str(self.src), "c")
        jid = json.loads(out)["id"]
        self.assertEqual(run("verify", str(self.root), jid)[0], 0)
        self.assertEqual(run("run", str(self.root), str(self.src), "c")[0], 1)                      # すでにある
        self.assertEqual(run("undo", str(self.root), jid)[0], 0)
        self.assertEqual(run("verify", str(self.root), "nothing")[0], 1)
        self.assertEqual(run("bogus")[0], 2)


if __name__ == "__main__":
    unittest.main()
