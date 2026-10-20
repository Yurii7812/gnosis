#!/usr/bin/env python3
import contextlib
import datetime as dt
import hashlib
import http.server
import io
import json
import sys
import tempfile
import threading
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import collector as co

NOW = dt.datetime(2026, 10, 21, 9, 0, 0)

RSS = """<?xml version="1.0" encoding="utf-8"?><rss version="2.0"><channel><title>T</title>
<item><title>最初の記事</title><link>https://example.com/a</link><guid>g1</guid><pubDate>Tue, 20 Oct 2026 09:00:00 GMT</pubDate>
<description><![CDATA[<p>本文です。<script>alert(1)</script><b>太字</b></p><p># 見出しに化けない</p><img src=x onerror=alert(1)>]]></description></item>
<item><title>二つ目 / 危険な: 名前?*</title><link>javascript:alert(1)</link><guid>g2</guid><description>要約2</description></item>
</channel></rss>"""
ATOM = """<?xml version="1.0"?><feed xmlns="http://www.w3.org/2005/Atom"><title>A</title>
<entry><title>アトムの記事</title><id>urn:a1</id><link rel="alternate" href="https://example.com/atom1"/><updated>2026-10-20T09:00:00Z</updated><summary>アトムの要約</summary></entry></feed>"""
XXE = """<?xml version="1.0"?><!DOCTYPE r [<!ENTITY x SYSTEM "file:///etc/passwd">]><rss><channel><item><title>&x;</title><guid>x</guid></item></channel></rss>"""
BOMB = """<?xml version="1.0"?><!DOCTYPE l [<!ENTITY a "aaaaaaaaaa"><!ENTITY b "&a;&a;&a;&a;&a;&a;&a;&a;&a;&a;">]><rss><channel><item><title>&b;</title><guid>b</guid></item></channel></rss>"""


class Handler(http.server.BaseHTTPRequestHandler):
    routes: dict = {}
    hits: list = []

    def do_GET(self):
        Handler.hits.append(self.path)
        r = Handler.routes.get(self.path)
        if r is None:
            self.send_response(404); self.end_headers(); return
        if isinstance(r, tuple) and r[0] == "redirect":
            self.send_response(302); self.send_header("Location", r[1]); self.end_headers(); return
        self.send_response(200); self.send_header("Content-Type", "application/xml"); self.end_headers()
        self.wfile.write(r if isinstance(r, bytes) else r.encode("utf-8"))

    def log_message(self, *a):
        pass


class Handler2(Handler):
    """別のホスト(ポート)。アクセス記録を分けて、リダイレクトで要求が届いていないことを確かめる。"""
    hits: list = []


class CollectorTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        cls.other = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler2)
        for s in (cls.srv, cls.other):
            threading.Thread(target=s.serve_forever, daemon=True).start()
        cls.base = f"http://127.0.0.1:{cls.srv.server_address[1]}"
        cls.base2 = f"http://127.0.0.1:{cls.other.server_address[1]}"

    @classmethod
    def tearDownClass(cls):
        cls.srv.shutdown(); cls.other.shutdown()

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(dir=str(Path.home() / "Desktop" / "test"))
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        (self.root / "keep.md").write_text("# 既存\n", encoding="utf-8")
        Handler.hits = []
        Handler2.hits = []
        Handler.routes = {"/rss": RSS, "/atom": ATOM, "/xxe": XXE, "/bomb": BOMB, "/big": b"<rss>" + b"x" * (co.MAX_BYTES + 10), "/redir": ("redirect", self.base2 + "/rss"),
                          "/redir-same": ("redirect", self.base + "/rss"), "/bad": "<rss><not closed", "/404x": ""}
        self.before = {str(p.relative_to(self.root)): hashlib.md5(p.read_bytes()).hexdigest() for p in self.root.rglob("*") if p.is_file()}

    def notes(self):
        return sorted(p for p in (self.root / "収集").glob("*.md")) if (self.root / "収集").is_dir() else []

    def test_default_is_no_network(self):
        co.allow(self.root, self.base + "/rss")
        calls = []
        r = co.run(self.root, fetch=lambda u: calls.append(u) or b"")
        self.assertFalse(r["ran"])
        self.assertIn("有効になっていません", r["reason"])
        self.assertEqual((calls, Handler.hits), ([], []))                                           # 無効なら、通信どころか取得関数も呼ばない
        co.set_enabled(self.root, True)
        co.deny(self.root, self.base + "/rss")
        r = co.run(self.root, fetch=lambda u: calls.append(u) or b"")
        self.assertFalse(r["ran"])
        self.assertIn("許可した URL がありません", r["reason"])
        self.assertEqual(calls, [])
        self.assertEqual(self.notes(), [])

    def test_allow_validation(self):
        for bad in ("ftp://x/y", "file:///etc/passwd", "javascript:alert(1)", "http://user:pw@host/x", "http:///nohost", "not a url", "http://h/" + "a" * 600):
            with self.assertRaises(ValueError, msg=bad):
                co.allow(self.root, bad)
        self.assertEqual(co.status(self.root)["allow"], [])
        # 手で書き換えた設定ファイルの不正な URL は読み込まない
        (self.root / ".gnosis").mkdir()
        (self.root / ".gnosis" / "collector.json").write_text(json.dumps({"enabled": "yes", "allow": ["file:///etc/passwd", self.base + "/rss", 5]}), encoding="utf-8")
        st = co.status(self.root)
        self.assertEqual(st["allow"], [self.base + "/rss"])
        self.assertFalse(st["enabled"])                                                             # true(真偽値)以外は無効

    def test_rss_creates_new_notes_only_and_sanitizes(self):
        co.set_enabled(self.root, True); co.allow(self.root, self.base + "/rss")
        r = co.run(self.root, now=NOW)
        self.assertEqual((r["ran"], r["new"], r["errors"]), (True, 2, 0))
        ns = self.notes()
        self.assertEqual(len(ns), 2)
        first = next(p for p in ns if "最初の記事" in p.name).read_text(encoding="utf-8")
        self.assertTrue(first.startswith("---\ntime: 2026-10-21 09:00:00\ntitle: 最初の記事\nsource: web\nfeed: "))
        self.assertIn("本文です。", first)
        self.assertIn("太字", first)
        self.assertNotIn("<script", first)
        self.assertNotIn("alert(1)", first)                                                         # スクリプトの中身も捨てる
        self.assertNotIn("<img", first)
        self.assertNotIn("\n# 見出しに化けない", first)                                               # 本文の行頭の # は見出しにならない
        self.assertIn("見出しに化けない", first)
        self.assertIn("[元の記事](https://example.com/a)", first)
        second = next(p for p in ns if "二つ目" in p.name).read_text(encoding="utf-8")
        self.assertNotIn("javascript:", second)                                                     # 危険なリンクは載せない
        self.assertNotIn("元の記事", second)
        self.assertTrue(all(not any(c in p.name for c in '/\\:*?"<>|') for p in ns))               # ファイル名に危険な文字が無い
        after = {str(p.relative_to(self.root)): hashlib.md5(p.read_bytes()).hexdigest() for p in self.root.rglob("*") if p.is_file() and "収集" not in p.parts and ".state" not in p.parts and ".gnosis" not in p.parts}
        self.assertEqual(after, self.before)                                                        # 既存のノートは不変

    def test_atom_and_dedupe_even_after_user_deletes_note(self):
        co.set_enabled(self.root, True); co.allow(self.root, self.base + "/atom")
        self.assertEqual(co.run(self.root, now=NOW)["new"], 1)
        n = self.notes()[0]
        self.assertIn("アトムの要約", n.read_text(encoding="utf-8"))
        self.assertIn("[元の記事](https://example.com/atom1)", n.read_text(encoding="utf-8"))
        self.assertEqual(co.run(self.root, now=NOW)["new"], 0)                                      # 2 回目は増えない
        n.unlink()
        self.assertEqual(co.run(self.root, now=NOW)["new"], 0)                                      # 消されても作り直さない
        self.assertEqual(self.notes(), [])

    def test_hostile_xml_is_refused(self):
        co.set_enabled(self.root, True)
        for path in ("/xxe", "/bomb", "/bad"):
            co.allow(self.root, self.base + path)
        r = co.run(self.root, now=NOW)
        self.assertEqual((r["new"], r["errors"]), (0, 3))
        self.assertTrue(all(f["error"] for f in r["feeds"]))
        self.assertEqual(self.notes(), [])
        self.assertTrue(any("DOCTYPE" in f["error"] for f in r["feeds"]))

    def test_size_limit_and_redirects(self):
        co.set_enabled(self.root, True)
        co.allow(self.root, self.base + "/big"); co.allow(self.root, self.base + "/redir"); co.allow(self.root, self.base + "/redir-same")
        r = co.run(self.root, now=NOW)
        by = {f["url"].rsplit("/", 1)[1]: f for f in r["feeds"]}
        self.assertIn("大きすぎ", by["big"]["error"])
        self.assertIn("別のホスト", by["redir"]["error"])                                            # 別ホスト(別ポート)へのリダイレクトは辿らない
        self.assertEqual(by["redir-same"]["new"], 2)                                                # 同じホストの中のリダイレクトは辿る
        self.assertEqual(Handler2.hits, [])                                                         # 別ホスト側には、リダイレクトを辿った要求が届いていない

    def test_one_bad_feed_does_not_stop_the_others(self):
        co.set_enabled(self.root, True)
        co.allow(self.root, self.base + "/xxe"); co.allow(self.root, self.base + "/rss"); co.allow(self.root, self.base + "/nothing")
        r = co.run(self.root, now=NOW)
        self.assertEqual((r["new"], r["errors"]), (2, 2))
        self.assertEqual(len(self.notes()), 2)
        self.assertEqual(co.status(self.root)["last_run"], "2026-10-21 09:00:00")

    def test_max_new_per_feed(self):
        items = "".join(f"<item><title>記事{i}</title><guid>g{i}</guid><description>d</description></item>" for i in range(40))
        Handler.routes["/many"] = f"<rss><channel>{items}</channel></rss>"
        co.set_enabled(self.root, True); co.allow(self.root, self.base + "/many")
        self.assertEqual(co.run(self.root, now=NOW)["new"], 20)
        self.assertEqual(co.run(self.root, now=NOW)["new"], 20)                                     # 続きは次回
        self.assertEqual(co.run(self.root, now=NOW)["new"], 0)

    def test_text_cleaning(self):
        self.assertEqual(co.to_text("<p>a</p><p>b</p>"), "a\n\nb")
        self.assertEqual(co.to_text("<script>x()</script>本文<style>p{}</style>"), "本文")
        self.assertEqual(co.to_text("&lt;b&gt; &amp; &quot;"), '<b> & "')                            # 実体参照は文字に戻す(Markdown としては文字のまま)
        self.assertEqual(len(co.to_text("あ" * 5000)), 1500)
        self.assertNotIn("\n#", "\n" + co.to_text("<p># h</p><p>> q</p><p>```x```</p>"))

    def test_cli(self):
        def run(*a):
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                rc = co.main([str(self.root), *a])
            return rc, buf.getvalue()
        self.assertEqual(run("status")[0], 0)
        self.assertEqual(run("allow", "ftp://x")[0], 1)
        self.assertEqual(run("allow", self.base + "/rss")[0], 0)
        self.assertEqual(json.loads(run("run")[1])["ran"], False)                                   # 有効にしていないので通信しない
        self.assertEqual(Handler.hits, [])
        self.assertEqual(run("enable")[0], 0)
        self.assertEqual(json.loads(run("run")[1])["new"], 2)
        self.assertEqual(run("deny", "http://nothing/")[0], 1)
        self.assertEqual(run("disable")[0], 0)
        self.assertEqual(run("bogus")[0], 2)


if __name__ == "__main__":
    unittest.main()
