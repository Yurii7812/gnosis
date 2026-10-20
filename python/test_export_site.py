#!/usr/bin/env python3
import json
import os
import re
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import export_site as ex


def note(root, name, title, body="", extra=""):
    (root / name).write_text(f"---\ntime: 2026-01-01 00:00:00\ntitle: {title}\n{extra}---\n\n# {title}\n\n{body}\n", encoding="utf-8")


class ExportTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(dir=str(Path.home() / "Desktop" / "test"))
        self.addCleanup(self.tmp.cleanup)
        base = Path(self.tmp.name)
        self.root = base / "vault"
        self.out = base / "site"
        self.root.mkdir()
        r = self.root
        (r / "pic.png").write_bytes(b"\x89PNG-fake")
        (r / "sub").mkdir()
        (r / "sub" / "doc.pdf").write_bytes(b"%PDF-fake")
        (base / "secret.txt").write_text("OUTSIDE", encoding="utf-8")
        os.symlink(base / "secret.txt", r / "leak.png")
        (r / ".hidden.png").write_bytes(b"x")
        note(r, "herb.md", "ハーブ", "BranchGroup:\n[栽培](grow.md)\n[秘密](priv.md)\n\n![図](pic.png) と ![漏れ](leak.png) と ![外](../secret.txt) と [資料](sub/doc.pdf)\n\n"
                              "<script>alert(1)</script> [悪](javascript:alert(1))\n", extra='folgezettel: "1"\n')
        note(r, "grow.md", "栽培", "ParentBranch:\n[ハーブ](herb.md)\n\n本文 **強調**\n", extra='folgezettel: "1a"\n')
        note(r, "priv.md", "秘密", "公開しない内容 TOPSECRET\n", extra="private: true\n")
        note(r, "sub/nested.md" if False else "nested.md", "入れ子", "[ハーブ](herb.md)\n")
        (r / "sub" / "deep.md").write_text("---\ntitle: 深い\n---\n\n# 深い\n\n[上](../herb.md)\n", encoding="utf-8")
        self.before = {p.relative_to(r).as_posix(): p.read_bytes() for p in r.rglob("*") if p.is_file() and not p.is_symlink()}

    def index(self):
        t = (self.out / "search-index.js").read_text(encoding="utf-8")
        assert t.startswith("window.GNOSIS_INDEX=")
        return json.loads(t[len("window.GNOSIS_INDEX="):].rstrip().rstrip(";"))

    def run_export(self, **kw):
        return ex.export(self.root, self.out, **kw)

    def test_basic_site(self):
        res = self.run_export()
        o = self.out
        self.assertEqual(res["skipped_private"], ["priv.md"])
        for f in ("index.html", "herb.html", "grow.html", "nested.html", "sub/deep.html", "folgezettel.html", "FOLGEZETTEL.md", "search.html", "search.js", "search-index.js", "style.css"):
            self.assertTrue((o / f).is_file(), f)
        herb = (o / "herb.html").read_text(encoding="utf-8")
        self.assertIn('<a href="grow.html">栽培</a>', herb)
        self.assertNotIn("priv.html", herb)             # 非公開へはリンクにしない（文字だけ）
        self.assertIn("秘密", herb)
        self.assertNotIn("TOPSECRET", "".join(p.read_text(encoding="utf-8", errors="ignore") for p in o.rglob("*") if p.is_file()))
        self.assertFalse((o / "priv.html").exists())
        self.assertIn('<a href="../herb.html">上</a>', (o / "sub/deep.html").read_text(encoding="utf-8"))   # 階層をまたぐ相対リンク
        self.assertIn("../style.css", (o / "sub/deep.html").read_text(encoding="utf-8"))
        # 逆向きの関係（栽培が ParentBranch でハーブを指す）も、ハーブのページから辿れる
        self.assertRegex(herb, r'このノートへのリンク</h2><ul>.*<a href="grow.html">栽培</a>')
        md = (o / "FOLGEZETTEL.md").read_text(encoding="utf-8")
        self.assertIn("| 1 | [ハーブ](herb.md) |", md)
        self.assertIn("| 　1a | [栽培](grow.md) |", md)

    def test_security(self):
        self.run_export()
        o = self.out
        herb = (o / "herb.html").read_text(encoding="utf-8")
        self.assertNotIn("<script>alert", herb)
        self.assertNotIn("javascript:", herb)
        for p in o.rglob("*.html"):
            t = p.read_text(encoding="utf-8")
            self.assertIn("Content-Security-Policy", t)
            self.assertIn("default-src 'none'", t)
            self.assertNotRegex(t, r"(?i)(src|href)=\"https?://")   # 外部 CDN を読まない
            self.assertNotRegex(re.sub(r'<script src="[\w./-]+\.js"></script>', "", t), r"<script")   # インラインのスクリプトは無い（自前の .js だけ）
            self.assertNotIn("fetch(", t)
        copied = sorted(p.relative_to(o).as_posix() for p in o.rglob("*") if p.is_file())
        self.assertIn("pic.png", copied)
        self.assertIn("sub/doc.pdf", copied)
        self.assertNotIn("leak.png", copied)              # シンボリックリンクで vault の外を持ち出さない
        self.assertNotIn("secret.txt", copied)
        self.assertNotIn(".hidden.png", copied)
        self.assertNotIn("OUTSIDE", "".join(p.read_text(encoding="utf-8", errors="ignore") for p in o.rglob("*") if p.is_file()))

    def test_graph_page_excludes_private_and_links_local_graph(self):
        self.run_export()
        t = (self.out / "graph-data.js").read_text(encoding="utf-8")
        self.assertTrue(t.startswith("window.GNOSIS_GRAPH="))
        data = json.loads(t[len("window.GNOSIS_GRAPH="):].rstrip().rstrip(";"))
        ids = {n["id"] for n in data["nodes"]}
        self.assertIn("herb.md", ids)
        self.assertNotIn("priv.md", ids)
        self.assertTrue(all(e["s"] in ids and e["d"] in ids for e in data["edges"]))   # 非公開への辺は残さない
        self.assertNotIn("秘密", t)
        kinds = {e["k"] for e in data["edges"]}
        self.assertTrue({"parent_branch", "branch_group"} <= kinds)                   # 種類を持ったまま
        for f in ("graph.html", "graph.js", "graphcore.js"):
            self.assertTrue((self.out / f).is_file(), f)
        self.assertIn("graph.html#n=herb.md&amp;depth=1", (self.out / "herb.html").read_text(encoding="utf-8").replace("&depth", "&amp;depth"))
        self.assertIn("../graph.html#n=sub/deep.md", (self.out / "sub/deep.html").read_text(encoding="utf-8").replace("%2F", "/"))

    def notes_data(self):
        t = (self.out / "notes-data.js").read_text(encoding="utf-8")
        assert t.startswith("window.GNOSIS_NOTES=")
        return json.loads(t[len("window.GNOSIS_NOTES="):].rstrip().rstrip(";"))

    def test_notes_data_for_cards_table_timeline(self):
        self.run_export()
        data = {n["id"]: n for n in self.notes_data()}
        self.assertNotIn("priv.md", data)                         # 非公開は一覧データにも出さない
        self.assertNotIn("TOPSECRET", (self.out / "notes-data.js").read_text(encoding="utf-8"))
        h = data["herb.md"]
        self.assertEqual((h["title"], h["fz"], h["href"], h["time"]), ("ハーブ", "1", "herb.html", "2026-01-01 00:00:00"))
        self.assertEqual(h["image"], "pic.png")                    # 最初の画像（コピー済みのもの）がカードの絵になる
        # 本文のタグ風の文字は抜粋に文字として残るが、描画側は textContent だけを使う（innerHTML を使わない）
        for js in ("views.js", "graph.js", "fznav.js", "bridge.js"):
            self.assertNotIn("innerHTML", (self.out / js).read_text(encoding="utf-8"), js)
            self.assertNotIn("document.write", (self.out / js).read_text(encoding="utf-8"), js)
        self.assertNotIn("](", h["excerpt"])                       # リンクの書き方は外す
        self.assertNotIn("BranchGroup", h["excerpt"])
        self.assertGreater(h["out"], 0)
        self.assertGreater(data["grow.md"]["out"], 0)              # ParentBranch で herb を指す
        self.assertGreater(h["in"], 0)
        self.assertGreater(h["size"], 10)
        for page, view in (("cards.html", "cards"), ("table.html", "table"), ("timeline.html", "timeline")):
            t = (self.out / page).read_text(encoding="utf-8")
            self.assertIn(f'data-view="{view}"', t)
            self.assertIn("Content-Security-Policy", t)
            self.assertNotIn("fetch(", t)

    def test_excerpt(self):
        e = ex._excerpt(["# 見出し", "", "本文 **強調** と [リンク](x.md) と ![図](a.png)", "- [ ] 項目", "```", "コード", "```", "BranchGroup:", "[子](c.md)"])
        self.assertEqual(e, "本文 強調 と リンク と 項目 子")
        self.assertEqual(len(ex._excerpt(["あ" * 500])), 180)

    def test_bridge_is_loaded_everywhere_and_only_posts_open(self):
        self.run_export()
        for p in self.out.rglob("*.html"):
            rel = p.relative_to(self.out).as_posix()
            self.assertIn('bridge.js"></script>', p.read_text(encoding="utf-8"), rel)
        self.assertIn('src="../bridge.js"', (self.out / "sub/deep.html").read_text(encoding="utf-8"))
        js = (self.out / "bridge.js").read_text(encoding="utf-8")
        self.assertIn('window.name !== "gnosis:open"', js)       # 埋め込まれたときだけ
        self.assertIn('postMessage({ gnosis: "open"', js)
        for bad in ("eval(", "fetch(", "XMLHttpRequest", "innerHTML", "document.write"):
            self.assertNotIn(bad, js)

    def test_include_private_and_search_index(self):
        self.run_export(include_private=True)
        self.assertTrue((self.out / "priv.html").is_file())
        idx = self.index()
        self.assertIn("秘密", [e["t"] for e in idx])

    def test_search_index_excludes_private_by_default(self):
        self.run_export()
        idx = self.index()
        self.assertNotIn("秘密", [e["t"] for e in idx])
        self.assertNotIn("topsecret", json.dumps(idx, ensure_ascii=False).lower())
        self.assertNotIn("fetch(", (self.out / "search.js").read_text(encoding="utf-8"))   # file:// で動くよう fetch を使わない

    def test_vault_untouched_and_rerunnable(self):
        self.run_export()
        self.run_export()                                 # 前回の書き出し先には上書きできる
        now = {p.relative_to(self.root).as_posix(): p.read_bytes() for p in self.root.rglob("*") if p.is_file() and not p.is_symlink()}
        self.assertEqual(self.before, now)                # vault のファイルは 1 バイトも変わらない・増えない

    def test_refuses_unsafe_output(self):
        keep = self.out
        keep.mkdir()
        (keep / "mine.txt").write_text("大事", encoding="utf-8")
        with self.assertRaises(ValueError):
            self.run_export()                             # 空でなく前回の書き出しでもない → 何も書かない
        self.assertEqual(sorted(p.name for p in keep.iterdir()), ["mine.txt"])
        with self.assertRaises(ValueError):
            ex.export(self.root, self.root / "site")      # vault の中（ドット始まりでない）
        with self.assertRaises(ValueError):
            ex.export(self.root, self.root)
        ex.export(self.root, self.root / ".site")         # ドット始まりなら vault の中でもよい
        self.assertTrue((self.root / ".site" / "index.html").is_file())
        visible = lambda d: {k: v for k, v in d.items() if not k.startswith(".")}
        now = {p.relative_to(self.root).as_posix(): p.read_bytes() for p in self.root.rglob("*") if p.is_file() and not p.is_symlink()}
        self.assertEqual(visible(self.before), visible(now))      # .site 以外は変わらない


if __name__ == "__main__":
    unittest.main()
