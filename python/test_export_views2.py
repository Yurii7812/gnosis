#!/usr/bin/env python3
import json
import re
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import export_site
import export_views2 as ev


def note(root, name, title, body, fm=""):
    (root / name).write_text(f"---\ntime: 2026-03-05 10:00:00\ntitle: {title}\n{fm}---\n\n# {title}\n\n{body}\n", encoding="utf-8")


def js_data(path: Path):
    text = path.read_text(encoding="utf-8")
    return json.loads(text[text.index("=") + 1:].rstrip().rstrip(";"))


class SlidesSplitTest(unittest.TestCase):
    def test_split_rules(self):
        md = "# 表紙\n\n導入\n\n---\n\n## 第一章\n\n- a\n- b\n\n## 第二章\n\n```\n---\n## これはコード\n```\n\n本文\n"
        s = ev.split_slides(md)
        self.assertEqual(len(s), 3)
        self.assertTrue(s[0].startswith("# 表紙"))
        self.assertTrue(s[1].startswith("## 第一章"))
        self.assertIn("## これはコード", s[2])                                   # コードの中の --- と ## では割らない
        self.assertEqual(ev.split_slides(""), [])
        self.assertEqual(len(ev.split_slides("a\n\n---\n\n---\n\nb")), 2)         # 空のスライドは作らない
        self.assertEqual(len(ev.split_slides("a\r\n---\r\nb")), 2)               # CRLF
        self.assertEqual(ev.split_slides("だけ"), ["だけ"])


class RebaseTest(unittest.TestCase):
    def test_rebase_relative_paths(self):
        r = ev.rebase_html
        self.assertEqual(r('<img src="p.png"><a href="o.html">x</a>', "sub/deck.md"), '<img src="sub/p.png"><a href="sub/o.html">x</a>')
        self.assertEqual(r('<a href="../top.html">x</a>', "sub/deck.md"), '<a href="top.html">x</a>')              # 上へ戻るものは正規化
        self.assertEqual(r('<a href="x.html#sec">x</a>', "a/b/c.md"), '<a href="a/b/x.html#sec">x</a>')            # #見出しは保つ
        self.assertEqual(r('<a href="../../t.html">x</a>', "a/b/c.md"), '<a href="t.html">x</a>')
        for same in ('<a href="https://e.com/a">x</a>', '<a href="mailto:a@b">x</a>', '<a href="#top">x</a>', '<a href="/abs">x</a>', '<img src="" alt="">', '<img src="data:image/png;base64,AAAA">'):
            self.assertEqual(r(same, "sub/deck.md"), same)                                                       # URL・#・絶対・空は触らない
        self.assertEqual(r('<img src="p.png">', "top.md"), '<img src="p.png">')                                  # 最上位のノートは不変


class ExportViews2Test(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(dir=str(Path.home() / "Desktop" / "test"))
        self.addCleanup(self.tmp.cleanup)
        base = Path(self.tmp.name)
        self.root, self.out = base / "v", base / "site"
        self.root.mkdir()
        r = self.root
        (r / "img").mkdir()
        (r / "img" / "p.png").write_bytes(b"\x89PNG")
        (r / "img" / "secret.png").write_bytes(b"SECRETPNG")
        (r / "doc.pdf").write_bytes(b"%PDF")
        note(r, "a.md", "ハーブ", "![図](img/p.png)と[資料](doc.pdf)\n- [ ] 水やり 📅 2026-10-25\n- [x] 買った ✅ 2026-10-20\n[秘密へ](secret.md)", "folgezettel: \"1\"\nlocation: 35.68, 139.76\n")
        note(r, "slides.md", "発表", "# 表紙\n\n導入\n\n---\n\n## 第一章\n\n本文\n\n<script>alert(1)</script>", "slides: true\n")
        note(r, "plain.md", "ふつう", "---\n\nスライドにしない", "")
        note(r, "secret.md", "TOPSECRET-TITLE", "TOPSECRET-BODY ![秘](img/secret.png)\n- [ ] TOPSECRET-TASK 📅 2026-10-01", "private: true\nlocation: 1.0, 2.0\nslides: true\n")
        self.res = export_site.export(self.root, self.out)

    def all_text(self):
        return {p.name: p.read_text(encoding="utf-8", errors="replace") for p in self.out.glob("*") if p.is_file() and p.suffix in (".html", ".js", ".css", ".md")}

    def test_all_pages_and_assets_exist(self):
        for key, *_ in ev.VIEWS:
            self.assertTrue((self.out / f"{key}.html").is_file(), key)
        for name in ("views.html", "views2core.js", "views2.js", "tasks-data.js", "files-data.js", "slides-data.js"):
            self.assertTrue((self.out / name).is_file(), name)
        index = (self.out / "index.html").read_text(encoding="utf-8")
        self.assertIn('href="views.html"', index)
        views = (self.out / "views.html").read_text(encoding="utf-8")
        for key, title, *_ in ev.VIEWS:
            self.assertIn(f'href="{key}.html"', views)

    def test_pages_have_csp_and_no_external_or_inline_script(self):
        for key, *_ in ev.VIEWS:
            t = (self.out / f"{key}.html").read_text(encoding="utf-8")
            self.assertIn("Content-Security-Policy", t)
            self.assertIn("default-src 'none'", t)
            self.assertEqual(re.findall(r"<script(?![^>]*\bsrc=)[^>]*>", t), [], key)       # インラインスクリプトなし
            self.assertIsNone(re.search(r'(?:src|href)="https?://', t), key)
            self.assertIsNone(re.search(r"\bstyle=", t), key)                               # インライン style なし(CSP の style-src 'self')
            self.assertIn(f'data-view2="{key}"', t)

    def test_private_note_never_appears_in_new_data_or_pages(self):
        for name, text in self.all_text().items():
            if name == "search-index.js":
                continue
            for needle in ("TOPSECRET", "secret.png", "SECRETPNG"):
                self.assertNotIn(needle, text, f"{name} に {needle} が漏れた")
        self.assertFalse((self.out / "img" / "secret.png").exists())
        notes = js_data(self.out / "notes-data.js")
        self.assertNotIn("secret.md", [n["id"] for n in notes])
        self.assertNotIn("1.0, 2.0", json.dumps(notes))                                     # 非公開の位置情報も出ない

    def test_tasks_data(self):
        tasks = js_data(self.out / "tasks-data.js")
        by = {t["text"]: t for t in tasks}
        self.assertEqual(set(by), {"水やり", "買った"})                                      # 非公開ノートのタスクは含めない
        self.assertEqual((by["水やり"]["due"], by["水やり"]["done"], by["水やり"]["href"]), ("2026-10-25", False, "a.html"))
        self.assertEqual((by["買った"]["done"], by["買った"]["done_date"]), (True, "2026-10-20"))
        self.assertGreater(by["水やり"]["line"], 0)

    def test_files_data_with_referencing_notes(self):
        files = {f["name"]: f for f in js_data(self.out / "files-data.js")}
        self.assertEqual(set(files), {"img/p.png", "doc.pdf"})                              # 非公開が参照する secret.png はコピーされず、載らない
        self.assertEqual([n["id"] for n in files["img/p.png"]["notes"]], ["a.md"])
        self.assertEqual(files["img/p.png"]["size"], 4)
        self.assertEqual(files["doc.pdf"]["notes"][0]["title"], "ハーブ")

    def test_slides_only_for_opted_in_and_sanitized(self):
        decks = js_data(self.out / "slides-data.js")
        self.assertEqual([d["id"] for d in decks], ["slides.md"])                           # plain.md(slides なし)と非公開は含めない
        slides = decks[0]["slides"]
        self.assertEqual(len(slides), 2)
        joined = "".join(slides)
        self.assertIn("第一章", joined)
        self.assertNotIn("<script>", joined)                                               # 本文中のスクリプトは文字にされる
        self.assertIn("&lt;script&gt;", joined)

    def test_slides_in_subfolder_get_site_relative_paths(self):
        (self.root / "sub").mkdir()
        (self.root / "sub" / "p.png").write_bytes(b"x")
        (self.root / "sub" / "other.md").write_text("# o\n", encoding="utf-8")
        note(self.root / "sub", "deck.md", "サブのデッキ", "![図](p.png)\n\n---\n\n[別](other.md)", "slides: true\n")
        export_site.export(self.root, self.out)
        deck = next(d for d in js_data(self.out / "slides-data.js") if d["id"] == "sub/deck.md")
        self.assertIn('src="sub/p.png"', deck["slides"][0])
        self.assertIn('href="sub/other.html"', deck["slides"][1])
        self.assertTrue((self.out / "sub" / "p.png").is_file() and (self.out / "sub" / "other.html").is_file())   # 補正した先に実際にある

    def test_location_in_notes_data(self):
        notes = {n["id"]: n for n in js_data(self.out / "notes-data.js")}
        self.assertEqual(notes["a.md"]["location"], "35.68, 139.76")
        self.assertEqual(notes["plain.md"]["location"], "")

    def test_style_added_once(self):
        css = (self.out / "style.css").read_text(encoding="utf-8")
        self.assertEqual(css.count("body.v2{"), 1)
        export_site.export(self.root, self.out)                                              # 再書き出しでも重複しない
        self.assertEqual((self.out / "style.css").read_text(encoding="utf-8").count("body.v2{"), 1)


if __name__ == "__main__":
    unittest.main()
