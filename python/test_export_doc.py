#!/usr/bin/env python3
import contextlib
import hashlib
import io
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import export_doc as ed

PNG = bytes.fromhex("89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c4890000000d49444154789c6360000002000001e221bc330000000049454e44ae426082")


def note(root, name, title, body, fz="", extra=""):
    (root / name).write_text(f"---\ntime: 2026-01-01 00:00:00\ntitle: {title}\n{('folgezettel: \"%s\"\n' % fz) if fz else ''}{extra}---\n\n# {title}\n\n{body}\n", encoding="utf-8")


class ExportDocTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(dir=str(Path.home() / "Desktop" / "test"))
        self.addCleanup(self.tmp.cleanup)
        base = Path(self.tmp.name)
        self.root, self.outdir = base / "v", base / "out"
        self.root.mkdir(); self.outdir.mkdir()
        r = self.root
        (r / "img").mkdir()
        (r / "img" / "p.png").write_bytes(PNG)
        note(r, "n10.md", "十番", "[ハーブ](n1.md) へ。[秘密](secret.md) と [外](https://e.com/x) と <b>生HTML</b>\n2 行目(段落内の改行)", "10")
        note(r, "n2.md", "二番", "![図](img/p.png)\n\n![外の画像](../outside.png)", "2")
        note(r, "n1.md", "ハーブ & <タイム>", "本文 [二番へ](n2.md#sec)", "1")
        note(r, "n1a.md", "栽培", "枝", "1a")
        note(r, "n1a1.md", "水やり", "孫", "1a1")
        note(r, "free.md", "番号なし", "自由", "")
        note(r, "secret.md", "秘密のタイトル", "TOPSECRET", "", "private: true\n")
        (r.parent / "outside.png").write_bytes(b"OUTSIDE")
        self.before = {str(p.relative_to(r)): hashlib.md5(p.read_bytes()).hexdigest() for p in r.rglob("*") if p.is_file()}

    def same(self):
        self.assertEqual(self.before, {str(p.relative_to(self.root)): hashlib.md5(p.read_bytes()).hexdigest() for p in self.root.rglob("*") if p.is_file()})

    def epub(self, **kw):
        out = self.outdir / kw.pop("name", "book.epub")
        info = ed.build_epub(self.root, out, kw.pop("title", "試験の本"), **kw)
        return out, info

    def test_epub_structure(self):
        out, info = self.epub()
        z = zipfile.ZipFile(out)
        first = z.infolist()[0]
        self.assertEqual((first.filename, first.compress_type), ("mimetype", zipfile.ZIP_STORED))      # 先頭・無圧縮
        self.assertEqual(z.read("mimetype"), b"application/epub+zip")
        self.assertIn("META-INF/container.xml", z.namelist())
        self.assertIsNone(z.testzip())
        # すべての XML が読める
        for n in z.namelist():
            if n.endswith((".xhtml", ".opf", ".xml")):
                ET.fromstring(z.read(n))
        opf = ET.fromstring(z.read("OEBPS/content.opf"))
        ns = {"o": "http://www.idpf.org/2007/opf", "dc": "http://purl.org/dc/elements/1.1/"}
        self.assertEqual(opf.find("o:metadata/dc:title", ns).text, "試験の本")
        manifest = {i.get("id"): i for i in opf.findall("o:manifest/o:item", ns)}
        spine = [i.get("idref") for i in opf.findall("o:spine/o:itemref", ns)]
        self.assertEqual(len(spine), info["chapters"])
        for idref in spine:
            self.assertIn(idref, manifest)
        for item in manifest.values():                                                               # マニフェストの全ファイルが実在
            self.assertIn("OEBPS/" + item.get("href"), z.namelist())
        self.assertEqual(sum(1 for i in manifest.values() if i.get("properties") == "nav"), 1)

    def test_chapters_in_folgezettel_order_and_private_excluded(self):
        out, info = self.epub()
        z = zipfile.ZipFile(out)
        nav = ET.fromstring(z.read("OEBPS/nav.xhtml"))
        titles = ["".join(a.itertext()) for a in nav.iter("{http://www.w3.org/1999/xhtml}a")]
        self.assertEqual(titles, ["ハーブ & <タイム>", "栽培", "水やり", "二番", "十番", "番号なし"])      # 1 < 1a < 1a1 < 2 < 10、番号なしは最後
        everything = b"".join(z.read(n) for n in z.namelist())
        self.assertNotIn("TOPSECRET".encode(), everything)
        self.assertNotIn("秘密のタイトル".encode(), everything)
        self.assertEqual(info["chapters"], 6)

    def test_text_is_escaped_and_valid_xhtml(self):
        out, _ = self.epub()
        z = zipfile.ZipFile(out)
        ch10 = next(z.read(n).decode() for n in z.namelist() if n.startswith("OEBPS/chapters/") and "生HTML" in z.read(n).decode())
        self.assertNotIn("<b>", ch10)                                                                 # 生 HTML は文字にされる
        self.assertIn("&lt;b&gt;生HTML&lt;/b&gt;", ch10)
        self.assertIn("<br/>", ch10)                                                                  # 段落内の改行は、閉じた空要素(XML として有効)
        self.assertEqual(ch10.count("<h1>"), 1)                                                       # 章の見出しは 1 つ(本文先頭の同じ題を重ねない)
        ET.fromstring(ch10.split("\n", 2)[2])                                                         # 宣言と DOCTYPE のあとが XML として読める
        head = next(z.read(n).decode() for n in z.namelist() if n.startswith("OEBPS/chapters/") and "ハーブ" in z.read(n).decode() and "<h1>1 ハーブ" in z.read(n).decode())
        self.assertIn("ハーブ &amp; &lt;タイム&gt;", head)                                            # 題の & < > はエスケープ

    def test_links_between_chapters_and_to_excluded_notes(self):
        out, _ = self.epub()
        z = zipfile.ZipFile(out)
        ch10 = next(z.read(n).decode() for n in z.namelist() if n.startswith("OEBPS/chapters/") and "生HTML" in z.read(n).decode())
        hrefs = re.findall(r'<a href="([^"]*)"', ch10)                                              # 本文のリンクだけ(head のスタイルシートは除く)
        self.assertTrue(any(h.endswith(".xhtml") and "/" not in h for h in hrefs), hrefs)           # ノート間は章のファイルへ
        for h in hrefs:
            self.assertTrue(h.startswith("http") or h.startswith("c") and h.split("#")[0] in {Path(n).name for n in z.namelist()}, h)   # 壊れたリンクなし
        self.assertIn("https://e.com/x", ch10)
        self.assertNotIn("secret", ch10.lower().replace("秘密", ""))                                  # 除いたノートへのリンクは文字だけ
        self.assertIn("秘密", ch10)
        ch2 = next(z.read(n).decode() for n in z.namelist() if n.startswith("OEBPS/chapters/") and "二番" in z.read(n).decode() and "<h1>2 二番" in z.read(n).decode())
        self.assertIn('src="../images/1.png"', ch2)

    def test_images_only_from_inside_vault(self):
        out, info = self.epub()
        z = zipfile.ZipFile(out)
        self.assertEqual(info["images"], 1)
        self.assertEqual(z.read("OEBPS/images/1.png"), PNG)
        self.assertFalse(any(n.startswith("OEBPS/images/") and z.read(n) == b"OUTSIDE" for n in z.namelist()))   # vault の外の画像は入れない
        self.assertNotIn(b"outside.png", b"".join(z.read(n) for n in z.namelist() if n.endswith(".xhtml")))
        opf = z.read("OEBPS/content.opf").decode()
        self.assertIn('media-type="image/png"', opf)

    def test_subtree_with_root(self):
        out, info = self.epub(name="sub.epub", start="ハーブ & <タイム>")
        nav = ET.fromstring(zipfile.ZipFile(out).read("OEBPS/nav.xhtml"))
        titles = ["".join(a.itertext()) for a in nav.iter("{http://www.w3.org/1999/xhtml}a")]
        self.assertEqual(titles, ["ハーブ & <タイム>", "栽培", "水やり"])                              # 起点と、その番号の下だけ
        out2, i2 = self.epub(name="one.epub", start="free.md")
        self.assertEqual(i2["chapters"], 1)                                                           # 番号のないノートは 1 章
        with self.assertRaises(ValueError):
            self.epub(name="x.epub", start="存在しない")

    def test_include_private_flag(self):
        out, info = self.epub(name="all.epub", include_private=True)
        self.assertEqual(info["chapters"], 7)
        self.assertIn("TOPSECRET".encode(), b"".join(zipfile.ZipFile(out).read(n) for n in zipfile.ZipFile(out).namelist()))

    def test_output_path_rules_and_read_only(self):
        (self.outdir / "exists.epub").write_bytes(b"x")
        for bad, msg in ((self.outdir / "exists.epub", "上書きしません"), (self.root / "inside.epub", "vault の中"), (self.outdir / "nodir" / "x.epub", "フォルダがありません")):
            with self.assertRaises(ValueError) as cm:
                ed.build_epub(self.root, bad)
            self.assertIn(msg, str(cm.exception))
        self.assertEqual((self.outdir / "exists.epub").read_bytes(), b"x")
        self.assertFalse((self.root / "inside.epub").exists())
        self.same()

    def test_empty_vault_refused(self):
        empty = Path(self.tmp.name) / "empty"
        empty.mkdir()
        with self.assertRaises(ValueError):
            ed.build_epub(empty, self.outdir / "e.epub")
        self.assertFalse((self.outdir / "e.epub").exists())

    def test_single_html(self):
        out = self.outdir / "book.html"
        info = ed.build_html(self.root, out, "一冊")
        t = out.read_text(encoding="utf-8")
        self.assertIn("<title>一冊</title>", t)
        self.assertIn('href="#ch1"', t)
        self.assertIn("data:image/png;base64,", t)                                                    # 画像は埋め込む
        self.assertNotIn("TOPSECRET", t)
        self.assertNotIn("<b>生HTML", t)
        self.assertIsNone(re.search(r'(?:src|href)="https?://', t.replace('href="https://e.com/x"', "")))
        ET_ok = t.count('<section class="chapter"')
        self.assertEqual(ET_ok, info["chapters"])
        self.assertIn("default-src 'none'", t)

    def test_pdf_missing_browser_reports_clearly(self):
        old = os.environ.get("GNOSIS_CHROME"), os.environ.get("PATH")
        try:
            os.environ["GNOSIS_CHROME"] = "/nonexistent/browser"
            os.environ["PATH"] = "/nonexistent"
            with self.assertRaises(ValueError) as cm:
                ed.build_pdf(self.root, self.outdir / "x.pdf")
            self.assertIn("ブラウザ", str(cm.exception))
            self.assertFalse((self.outdir / "x.pdf").exists())                                         # 作れないときは何も作らない
        finally:
            for k, v in zip(("GNOSIS_CHROME", "PATH"), old):
                if v is None:
                    os.environ.pop(k, None)
                else:
                    os.environ[k] = v

    def test_pdf_with_real_headless_browser_if_available(self):
        exe = ed.find_browser()
        if not exe:
            cand = sorted((Path.home() / ".cache" / "ms-playwright").glob("chromium_headless_shell-*/chrome-headless-shell-linux64/chrome-headless-shell"))
            exe = str(cand[-1]) if cand else None
        if not exe:
            self.skipTest("headless 対応のブラウザが無いので PDF の実生成は省略（未検証）")
        os.environ["GNOSIS_CHROME"] = exe
        try:
            out = self.outdir / "book.pdf"
            info = ed.build_pdf(self.root, out, "PDF の本")
        finally:
            os.environ.pop("GNOSIS_CHROME", None)
        data = out.read_bytes()
        self.assertEqual(data[:5], b"%PDF-")
        self.assertGreater(len(data), 1000)
        self.assertEqual(info["chapters"], 6)
        if shutil.which("pdftotext"):                                                                 # 中身の文字(日本語)が入っていることを確かめる
            text = subprocess.run(["pdftotext", "-layout", str(out), "-"], capture_output=True, text=True).stdout
            for needle in ("PDF の本", "二番", "十番", "水やり"):
                self.assertIn(needle, text)
            self.assertNotIn("TOPSECRET", text)
        self.same()

    def test_cli(self):
        def run(*a):
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                rc = ed.main([str(self.root), *a])
            return rc, buf.getvalue()
        self.assertEqual(run("epub", str(self.outdir / "c.epub"), "--title", "CLI")[0], 0)
        self.assertEqual(run("epub", str(self.outdir / "c.epub"))[0], 1)
        self.assertEqual(run("html", str(self.outdir / "c.html"), "--root", "ハーブ & <タイム>")[0], 0)
        self.assertEqual(run("epub")[0], 2)
        self.assertEqual(run("docx", "x")[0], 2)


if __name__ == "__main__":
    unittest.main()
