#!/usr/bin/env python3
"""pdf_notes.py の試験。手書きの PDF（ハイライト・コメント・ページ木・圧縮オブジェクトストリーム）を作って確かめる。"""
import json, os, shutil, sys, tempfile, unittest, zlib
from pathlib import Path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pdf_notes as pn

HAVE = shutil.which("pdftotext") and shutil.which("pdfinfo")


def build_pdf(pages, annots, objstm=False):
    """pages: [本文の行リスト]。annots: {ページ番号: [注釈辞書の中身(文字列)]}。座標は左下原点、行は y=700,680…。"""
    objs = {}
    n = 3
    kids = []
    for i, lines in enumerate(pages, 1):
        pid, cid = n, n + 1
        n += 2
        stream = "BT /F1 12 Tf " + " ".join(f"1 0 0 1 72 {700 - 20 * j} Tm ({ln}) Tj" for j, ln in enumerate(lines)) + " ET"
        objs[cid] = f"<< /Length {len(stream)} >>\nstream\n{stream}\nendstream"
        an = ""
        ids = []
        for a in annots.get(i, []):
            objs[n] = "<< /Type /Annot " + a + f" /P {pid} 0 R >>"
            ids.append(n)
            n += 1
        if ids:
            an = "/Annots [" + " ".join(f"{x} 0 R" for x in ids) + "]"
        objs[pid] = f"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents {cid} 0 R /Resources << /Font << /F1 << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> >> >> {an} >>"
        kids.append(pid)
    objs[1] = "<< /Type /Catalog /Pages 2 0 R >>"
    objs[2] = f"<< /Type /Pages /Kids [{' '.join(f'{k} 0 R' for k in kids)}] /Count {len(kids)} >>"
    out = bytearray(b"%PDF-1.5\n")
    offs = {}
    if objstm:   # ページ・ページ木・Catalog・注釈をオブジェクトストリームに入れる(ストリームを持つ内容は除く)
        packed = [k for k, v in objs.items() if "stream" not in v]
        body, idx, pos = "", "", 0
        for k in packed:
            idx += f"{k} {pos} "
            body += objs[k] + "\n"
            pos += len(objs[k]) + 1
        data = zlib.compress((idx + body).encode())
        sid = n
        for k, v in objs.items():
            if k not in packed:
                offs[k] = len(out); out += f"{k} 0 obj\n{v}\nendobj\n".encode()
        offs[sid] = len(out)
        out += f"{sid} 0 obj\n<< /Type /ObjStm /N {len(packed)} /First {len(idx)} /Filter /FlateDecode /Length {len(data)} >>\nstream\n".encode() + data + b"\nendstream\nendobj\n"
    else:
        for k in sorted(objs):
            offs[k] = len(out); out += f"{k} 0 obj\n{objs[k]}\nendobj\n".encode()
    x = len(out)
    if objstm:     # xref ストリーム(圧縮オブジェクトは type 2: ストリーム番号と中の位置)
        xid = sid + 1
        offs[xid] = x
        top = xid + 1
        rows = b"\x00\x00\x00\x00\x00\x00\xff"
        for k in range(1, top):
            if k in packed:
                rows += b"\x02" + sid.to_bytes(4, "big") + packed.index(k).to_bytes(2, "big")
            elif k in offs:
                rows += b"\x01" + offs[k].to_bytes(4, "big") + b"\x00\x00"
            else:
                rows += b"\x00\x00\x00\x00\x00\x00\xff"
        data = zlib.compress(rows)
        out += f"{xid} 0 obj\n<< /Type /XRef /Size {top} /W [1 4 2] /Root 1 0 R /Filter /FlateDecode /Length {len(data)} >>\nstream\n".encode() + data + b"\nendstream\nendobj\n"
        out += f"startxref\n{x}\n%%EOF\n".encode()
        return bytes(out)
    top = max(offs) + 1
    out += f"xref\n0 {top}\n0000000000 65535 f \n".encode()
    for k in range(1, top):
        out += (f"{offs[k]:010d} 00000 n \n" if k in offs else "0000000000 65535 f \n").encode()
    out += f"trailer\n<< /Size {top} /Root 1 0 R >>\nstartxref\n{x}\n%%EOF\n".encode()
    return bytes(out)


def quad(x0, y0, x1, y1):   # 左下原点
    return f"/QuadPoints [{x0} {y1} {x1} {y1} {x0} {y0} {x1} {y0}] /Rect [{x0} {y0} {x1} {y1}]"


@unittest.skipUnless(HAVE, "poppler が無い")
class T(unittest.TestCase):
    def setUp(self):
        self.d = Path(tempfile.mkdtemp(dir=os.environ.get("TMPDIR")))
        self.addCleanup(shutil.rmtree, self.d, True)

    def pdf(self, name="b.pdf", objstm=False):
        pages = [["Alpha beta gamma delta", "second line epsilon zeta"], ["Page two has memory palace technique", "and spaced repetition works"]]
        # p1 の 1 行目(y=700 のベースライン。文字の高さ約 12): 全体の左半分をハイライト
        annots = {1: ["/Subtype /Highlight /C [1 1 0] " + quad(70, 697, 150, 712) + " /Contents (important \\(check\\))"],
                  2: ["/Subtype /Text /Rect [10 10 20 20] /Contents <FEFF30E1 30E2> /T (me)",
                      "/Subtype /Underline " + quad(70, 677, 200, 692)]}
        (self.d / name).write_bytes(build_pdf(pages, annots, objstm))
        return name

    def test_annotations(self):
        for objstm in (False, True):
            n = self.pdf(objstm=objstm)
            r = pn.annotations(self.d, n)
            self.assertEqual(r["pages"], 2)
            a = r["annotations"]
            self.assertEqual([x["kind"] for x in a], ["Highlight", "Text", "Underline"], objstm)
            self.assertEqual(a[0]["page"], 1)
            self.assertEqual(a[0]["text"], "Alpha beta")                   # QuadPoints 内の単語だけ
            self.assertEqual(a[0]["contents"], "important (check)")        # エスケープ
            self.assertEqual(a[1]["contents"], "メモ")                     # UTF-16BE の 16 進
            self.assertEqual(a[2]["page"], 2)
            self.assertTrue(a[2]["text"].startswith("and spaced"), a[2]["text"])

    def test_no_annotations_and_errors(self):
        (self.d / "e.pdf").write_bytes(build_pdf([["x y z"]], {}))
        self.assertEqual(pn.annotations(self.d, "e.pdf")["annotations"], [])
        with self.assertRaises(pn.PdfError): pn.digest(self.d, "e.pdf")
        (self.d / "bad.pdf").write_bytes(b"not a pdf")
        with self.assertRaises(pn.PdfError): pn.annotations(self.d, "bad.pdf")
        with self.assertRaises(pn.PdfError): pn.annotations(self.d, "../x.pdf")
        with self.assertRaises(pn.PdfError): pn.annotations(self.d, "missing.pdf")
        (self.d / "enc.pdf").write_bytes(build_pdf([["x"]], {}).replace(b"/Root 1 0 R", b"/Root 1 0 R /Encrypt 9 0 R"))
        with self.assertRaises(pn.PdfError): pn.annotations(self.d, "enc.pdf")

    def test_digest_writes_new_only(self):
        n = self.pdf()
        r = pn.digest(self.d, n, "notes/読書.md")
        self.assertIn("[p.1](b.pdf#page=1)", r["draft"])
        self.assertIn("> Alpha beta", r["draft"])
        self.assertIn("コメント: important (check)", r["draft"])
        t = (self.d / "notes/読書.md").read_text()
        self.assertTrue(t.startswith("---\ntime: "))
        with self.assertRaises(pn.PdfError): pn.digest(self.d, n, "notes/読書.md")       # 上書きしない
        with self.assertRaises(pn.PdfError): pn.digest(self.d, n, "../out.md")
        with self.assertRaises(pn.PdfError): pn.digest(self.d, n, ".hidden/x.md")
        self.assertFalse((self.d / ".hidden").exists())

    def test_check_quotes(self):
        self.pdf()
        (self.d / "n.md").write_text("---\ntime: 2026-01-01 00:00:00\ntitle: n\n---\n\n"
            "> Page two has memory palace technique [p.2](b.pdf#page=2)\n\n"          # 一致
            "> memory  palace\n> technique — [p.1](b.pdf#page=1)\n\n"                  # ずれ(p.2 にある)
            "> 存在しない引用文章です [p.1](b.pdf#page=1)\n\n"                         # どこにも無い
            "> Alpha beta gamma [p.9](b.pdf#page=9)\n\n"                              # ページが無い
            "```\n> Page two has memory palace [p.1](b.pdf#page=1)\n```\n"            # コード内は見ない
            "短い [p.1](b.pdf#page=1)\n", encoding="utf-8")
        r = pn.check(self.d)
        by = {(x["line"]): x for x in r["refs"]}
        st = sorted(x["status"] for x in r["refs"])
        self.assertEqual(r["counts"], {"ok": 1, "mismatch": 2, "unreadable": 1}, r)
        mm = [x for x in r["refs"] if x["status"] == "mismatch" and x["found_on"]]
        self.assertEqual(mm[0]["found_on"], [2])
        self.assertIn("見つかりません", pn.to_md("check", r))
        self.assertEqual(pn.check(self.d, "n.md")["counts"], r["counts"])
        self.assertEqual(pn.check(self.d, "none.md")["refs"], [])

    def test_page_and_cli(self):
        n = self.pdf()
        self.assertIn("memory palace", pn.page_text(self.d / n, 2))
        self.assertEqual(pn.main([str(self.d), "page", n, "1", "--md"]), 0)
        self.assertEqual(pn.main([str(self.d), "annotations", "nope.pdf"]), 1)


if __name__ == "__main__":
    unittest.main()
