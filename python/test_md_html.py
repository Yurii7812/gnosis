#!/usr/bin/env python3
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import md_html as mh


class MdHtmlTest(unittest.TestCase):
    def test_blocks(self):
        h = mh.render("# 題\n\n本文 **太字** と *斜体* と `code` と ~~消~~\n\n- 一\n- [ ] 二\n  - 入れ子\n- [x] 三\n\n1. a\n2. b\n\n> 引用\n\n---\n")
        self.assertIn("<h1>題</h1>", h)
        self.assertIn("<strong>太字</strong>", h)
        self.assertIn("<em>斜体</em>", h)
        self.assertIn("<code>code</code>", h)
        self.assertIn("<del>消</del>", h)
        self.assertIn('<li class="task">☐ 二<ul><li>入れ子</li></ul></li>', h)
        self.assertIn('<li class="task done">☑ 三</li>', h)
        self.assertIn("<ol><li>a</li><li>b</li></ol>", h)
        self.assertIn("<blockquote><p>引用</p></blockquote>", h)
        self.assertIn("<hr>", h)

    def test_table_and_code_fence(self):
        h = mh.render("| 番号 | 題 |\n|---|---|\n| 1 | [A](a.md) |\n\n```py\nif a < b:\n    print('<x>')\n```\n")
        self.assertIn("<th>番号</th>", h)
        self.assertIn('<td><a href="a.html">A</a></td>', h)
        self.assertIn("if a &lt; b:", h)            # コードの中身もエスケープ
        self.assertIn("&lt;x&gt;", h)
        self.assertNotIn("<x>", h)

    def test_links_rewrite_and_safety(self):
        self.assertEqual(mh.safe_url("note.md"), "note.html")
        self.assertEqual(mh.safe_url("sub/n.md#sec"), "sub/n.html#sec")
        self.assertEqual(mh.safe_url("https://e.com/a.md"), "https://e.com/a.md")   # 外部は書き換えない
        self.assertEqual(mh.safe_url("img.jpg"), "img.jpg")
        for bad in ("javascript:alert(1)", "JavaScript:alert(1)", "data:text/html;base64,xx", "vbscript:x", "file:///etc/passwd", "//evil.com/x"):
            self.assertIsNone(mh.safe_url(bad), bad)
        h = mh.inline("[x](javascript:alert(1)) と ![i](data:image/svg+xml;base64,AA)")
        self.assertNotIn("href", h)
        self.assertNotIn("<img", h)
        self.assertNotIn("javascript", h.split("x")[0])

    def test_no_raw_html(self):
        h = mh.render("<script>alert(1)</script>\n\n本文 <b onclick=x>b</b> & \"q\"\n\n[a\"onmouseover=\"x](u.md)\n")
        self.assertNotIn("<script>", h)
        self.assertNotIn("<b ", h)
        self.assertIn("&lt;script&gt;", h)
        self.assertIn("&amp;", h)
        # どのタグにも、許した名前以外の属性（onclick・onmouseover など）が付かない。引用符が入っても属性値を抜け出せない
        for src in (h, mh.inline('[x](u.md?a="b" onmouseover="c)'), mh.inline('![a" onerror="x](p.png)')):
            self.assertEqual(self.attr_names(src) - {"href", "src", "alt", "loading", "class"}, set(), src)

    @staticmethod
    def attr_names(markup: str) -> set:
        from html.parser import HTMLParser
        names: set = set()

        class P(HTMLParser):
            def handle_starttag(self, tag, attrs):
                names.update(k for k, _ in attrs)
        P().feed(markup)
        return names
        self.assertIn('<a href="u.html">', h)

    def test_code_and_images_not_mangled(self):
        h = mh.inline("`a*b*c` と ![図](a b.png)")
        self.assertIn("<code>a*b*c</code>", h)
        h = mh.inline("![図](pic.png)")
        self.assertIn('<img src="pic.png" alt="図" loading="lazy">', h)

    def test_link_label_with_code_or_image_does_not_crash(self):
        """実バグ: リンクの表示文字にコード・画像があると IndexError で書き出し全体が止まっていた。"""
        self.assertEqual(mh.inline("[`code`](x.md)"), '<a href="x.html"><code>code</code></a>')
        self.assertEqual(mh.inline("[![img](a.png)](x.md)"), '<a href="x.html"><img src="a.png" alt="img" loading="lazy"></a>')
        self.assertEqual(mh.inline("[a `b` c](x.md) and `d`"), '<a href="x.html">a <code>b</code> c</a> and <code>d</code>')
        self.assertEqual(mh.inline("**[`k`](x.md)**"), '<strong><a href="x.html"><code>k</code></a></strong>')
        self.assertEqual(mh.inline("`a` [b](x.md) `c`"), '<code>a</code> <a href="x.html">b</a> <code>c</code>')
        # 安全性: ラベルの中の HTML は文字にされる・危険なリンク先は文字だけ
        self.assertEqual(mh.inline("[`<script>alert(1)</script>`](x.md)"), '<a href="x.html"><code>&lt;script&gt;alert(1)&lt;/script&gt;</code></a>')
        out = mh.inline("[`code`](javascript:alert(1))")
        self.assertNotIn("<a", out)
        self.assertNotIn("\x00", mh.inline("[`a`](x.md) [`b`](y.md) ![i](z.png) `c`"))     # 退避の印が出力に残らない
        # 本文全体でも落ちない
        self.assertIn("<code>x</code>", mh.render("# 題\n\n- [`x`](a.md) と [![i](p.png)](b.md)\n"))

    def test_japanese_snake_case_not_italic(self):
        self.assertNotIn("<em>", mh.inline("snake_case_name と file_name_x"))


if __name__ == "__main__":
    unittest.main()
