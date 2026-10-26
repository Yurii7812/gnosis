#!/usr/bin/env python3
import contextlib
import datetime as dt
import hashlib
import io
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import templates as tp

NOW = dt.datetime(2026, 10, 21, 9, 5, 7)    # 水曜日


class TemplatesTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(dir=str(Path.home() / "gnosis-work" / "test"))
        self.addCleanup(self.tmp.cleanup)
        r = self.root = Path(self.tmp.name)
        (r / "テンプレート").mkdir()
        (r / "テンプレート" / "会議.md").write_text("# {{title}} {{date}}（{{weekday}}）\n\n- 日時: {{datetime}}\n- 参加者: {{cursor}}\n- 決定: {{cursor}}\n\n{{unknown}} と {{ date }}\n", encoding="utf-8")
        (r / "テンプレート" / "sub").mkdir()
        (r / "テンプレート" / "sub" / "付き.md").write_text("---\ntime: 固定\ntitle: {{title}}\n---\n\n本文 {{cursor}}\n", encoding="utf-8")
        (r / "他.md").write_text("# 他\n", encoding="utf-8")
        self.before = {str(p.relative_to(r)): hashlib.md5(p.read_bytes()).hexdigest() for p in r.rglob("*.md")}

    def test_list(self):
        names = [t["name"] for t in tp.list_templates(self.root)["templates"]]
        self.assertEqual(names, ["会議", "sub/付き"])
        self.assertEqual(tp.list_templates(self.root, "無い")["templates"], [])
        with self.assertRaises(ValueError):
            tp.list_templates(self.root, "../outside")

    def test_render_replaces_markers_only(self):
        r = tp.render(self.root, "会議", "週次", NOW)
        t = r["text"].split("\n")
        self.assertEqual(t[0], "# 週次 2026-10-21（水）")
        self.assertEqual(t[2], "- 日時: 2026-10-21 09:05:07")
        self.assertEqual(t[3], "- 参加者: ")                                      # 1 つ目のカーソル記号は消える
        self.assertEqual(t[4], "- 決定: ")                                         # 2 つ目も消える(残さない)
        self.assertEqual(t[6], "{{unknown}} と 2026-10-21")                        # 知らない記号はそのまま・空白入りの記号も解釈
        self.assertEqual(r["cursor"], {"line": 4, "col": len("- 参加者: ") + 1})  # カーソルは 1 つ目の位置(文字数ベース)

    def test_no_code_execution_or_nested_expansion(self):
        (self.root / "テンプレート" / "危険.md").write_text("{{__import__('os').system('id')}} {{title}} {{date}}\n", encoding="utf-8")
        r = tp.render(self.root, "危険", "{{date}}", NOW)
        self.assertEqual(r["text"].strip(), "{{__import__('os').system('id')}} {{date}} 2026-10-21")   # 題に入れた {{date}} は再展開しない

    def test_new_note_adds_front_matter_and_never_overwrites(self):
        r = tp.new_note(self.root, "会議", "議事/2026-10-21.md", "週次", NOW)
        text = (self.root / "議事" / "2026-10-21.md").read_text(encoding="utf-8")
        self.assertTrue(text.startswith("---\ntime: 2026-10-21 09:05:07\ntitle: 週次\n---\n\n# 週次 2026-10-21（水）"))
        self.assertEqual(text.split("\n")[r["cursor"]["line"] - 1][:6], "- 参加者:")      # 足した front matter の分だけカーソル行がずれる
        r2 = tp.new_note(self.root, "sub/付き", "n2.md", "題", NOW)
        t2 = (self.root / "n2.md").read_text(encoding="utf-8")
        self.assertTrue(t2.startswith("---\ntime: 固定\ntitle: 題\n---\n"))             # front matter があるテンプレートはそのまま(足さない)
        self.assertEqual(t2.count("---"), 2)
        self.assertEqual(r2["cursor"]["line"], 6)
        for bad, msg in (("n2.md", "上書きしません"), ("../x.md", "vault の外"), (".s/x.md", "ドット"), ("x.txt", ".md")):
            with self.assertRaises(ValueError, msg=bad) as cm:
                tp.new_note(self.root, "会議", bad, "t", NOW)
            self.assertIn(msg, str(cm.exception))
        with self.assertRaises(ValueError):
            tp.new_note(self.root, "ない", "z.md", "t", NOW)
        self.assertFalse((self.root / "z.md").exists())
        after = {k: v for k, v in {str(p.relative_to(self.root)): hashlib.md5(p.read_bytes()).hexdigest() for p in self.root.rglob("*.md")}.items() if k in self.before}
        self.assertEqual(after, self.before)                                      # テンプレートも既存ノートも不変

    def test_template_path_cannot_escape(self):
        (self.root.parent / "secret.md").write_text("秘密", encoding="utf-8")
        try:
            for name in ("../secret", "../../secret", "/etc/passwd"):
                with self.assertRaises(ValueError, msg=name):
                    tp.render(self.root, name)
        finally:
            (self.root.parent / "secret.md").unlink()

    def test_cli(self):
        def run(*a):
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                rc = tp.main([str(self.root), *a])
            return rc, buf.getvalue()
        self.assertEqual(json.loads(run("list")[1])["templates"][0]["name"], "会議")
        self.assertIn("2026-10-21", run("render", "会議", "--title", "T", "--now", "2026-10-21T09:00")[1])
        self.assertEqual(run("new", "会議", "c.md", "--now", "2026-10-21T09:00")[0], 0)
        self.assertEqual(run("new", "会議", "c.md")[0], 1)
        self.assertEqual(run("render", "ない")[0], 1)
        self.assertEqual(run("bogus")[0], 2)


if __name__ == "__main__":
    unittest.main()
