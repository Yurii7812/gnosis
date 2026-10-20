#!/usr/bin/env python3
"""Gnosis のノートが使う範囲の Markdown を HTML にする（依存なし・オフライン）。

対応: 見出し・段落・箇条書き（入れ子・チェックボックス）・番号つき・引用・コードブロック・表・水平線・
画像・リンク・強調・取り消し線・インラインコード。YAML front matter は読まない（呼び出し側で除く）。
安全: 本文のテキストは全部エスケープする。生の HTML は通さない。リンク・画像の URL は
http / https / mailto / 相対パスだけ通し、javascript: などは無効なリンクにする。
`.md` へのリンクは `.html` に書き換える（`rewrite_md_links`）。
"""
from __future__ import annotations

import html
import re

_SAFE_SCHEMES = ("http://", "https://", "mailto:")
_SCHEME_RE = re.compile(r"^[A-Za-z][A-Za-z0-9+.-]*:")


def safe_url(url: str, rewrite_md: bool = True) -> str | None:
    """通せない URL は None。相対パスの .md は .html にする。"""
    url = url.strip()
    if url.startswith("<") and url.endswith(">"):
        url = url[1:-1]
    url = url.split(' "', 1)[0].strip()
    if _SCHEME_RE.match(url) and not url.lower().startswith(_SAFE_SCHEMES):
        return None
    if url.startswith("//"):
        return None
    if rewrite_md and not _SCHEME_RE.match(url):
        path, sep, frag = url.partition("#")
        if path.lower().endswith(".md"):
            path = path[:-3] + ".html"
        url = path + sep + frag
    return url


_CODE = re.compile(r"(`+)(.+?)\1")
_IMG = re.compile(r"!\[((?:\\.|[^\]\\])*)\]\(([^)\s]+(?:\s+\"[^\"]*\")?)\)")
_LINK = re.compile(r"\[((?:\\.|[^\]\\])*)\]\(([^)]+)\)")
_STRONG = re.compile(r"\*\*(.+?)\*\*|__(.+?)__")
_EM = re.compile(r"(?<![\w*])\*(?!\s)(.+?)(?<!\s)\*(?![\w*])|(?<![\w_])_(?!\s)(.+?)(?<!\s)_(?![\w_])")
_DEL = re.compile(r"~~(.+?)~~")


def inline(text: str) -> str:
    stash: list[str] = []

    def keep(h: str) -> str:
        stash.append(h)
        return f"\x00{len(stash) - 1}\x00"

    text = _CODE.sub(lambda m: keep("<code>" + html.escape(m.group(2).strip()) + "</code>"), text)

    def img(m):
        u = safe_url(m.group(2), rewrite_md=False)
        alt = html.escape(re.sub(r"\\(.)", r"\1", m.group(1)), quote=True)
        return keep(f'<img src="{html.escape(u, quote=True)}" alt="{alt}" loading="lazy">') if u is not None else keep(alt)
    text = _IMG.sub(img, text)

    def link(m):
        u = safe_url(m.group(2))
        label = inline(re.sub(r"\\(.)", r"\1", m.group(1)))
        return keep(f'<a href="{html.escape(u, quote=True)}">{label}</a>') if u is not None else keep(label)
    text = _LINK.sub(link, text)
    text = html.escape(text, quote=False)
    text = _STRONG.sub(lambda m: "<strong>" + (m.group(1) or m.group(2)) + "</strong>", text)
    text = _EM.sub(lambda m: "<em>" + (m.group(1) or m.group(2)) + "</em>", text)
    text = _DEL.sub(lambda m: "<del>" + m.group(1) + "</del>", text)
    return re.sub(r"\x00(\d+)\x00", lambda m: stash[int(m.group(1))], text)


_LIST = re.compile(r"^(\s*)([-*+]|\d+[.)])\s+(.*)$")
_TABLE_SEP = re.compile(r"^\s*\|?\s*:?-{2,}:?\s*(\|\s*:?-{2,}:?\s*)*\|?\s*$")


def _cells(line: str) -> list[str]:
    s = line.strip()
    if s.startswith("|"):
        s = s[1:]
    if s.endswith("|") and not s.endswith("\\|"):
        s = s[:-1]
    return [c.strip().replace("\\|", "|") for c in re.split(r"(?<!\\)\|", s)]


def _render_list(lines: list[str], i: int, indent: int) -> tuple[str, int]:
    m = _LIST.match(lines[i])
    ordered = m.group(2)[0].isdigit()
    tag = "ol" if ordered else "ul"
    out = [f"<{tag}>"]
    while i < len(lines):
        m = _LIST.match(lines[i])
        if not m or len(m.group(1).replace("\t", "    ")) != indent:
            break
        body = m.group(3)
        cls = ""
        cb = re.match(r"^\[([ xX])\]\s?(.*)$", body)
        if cb:
            checked = cb.group(1) in "xX"
            body = ("☑ " if checked else "☐ ") + cb.group(2)
            cls = ' class="task done"' if checked else ' class="task"'
        item = inline(body)
        i += 1
        if i < len(lines):
            nm = _LIST.match(lines[i])
            if nm and len(nm.group(1).replace("\t", "    ")) > indent:
                sub, i = _render_list(lines, i, len(nm.group(1).replace("\t", "    ")))
                item += sub
        out.append(f"<li{cls}>{item}</li>")
    out.append(f"</{tag}>")
    return "".join(out), i


def render(md: str) -> str:
    lines = md.replace("\r\n", "\n").split("\n")
    out: list[str] = []
    i = 0
    para: list[str] = []

    def flush():
        nonlocal para
        if para:
            out.append("<p>" + "<br>\n".join(inline(p.strip()) for p in para) + "</p>")
            para = []

    while i < len(lines):
        ln = lines[i]
        s = ln.strip()
        fence = re.match(r"^(\s*)(```|~~~)\s*([\w+-]*)", ln)
        if fence:
            flush()
            mark = fence.group(2)
            i += 1
            code = []
            while i < len(lines) and not lines[i].strip().startswith(mark):
                code.append(lines[i])
                i += 1
            i += 1
            lang = fence.group(3)
            out.append(f'<pre><code{f" class=\"language-{html.escape(lang)}\"" if lang else ""}>' + html.escape("\n".join(code)) + "</code></pre>")
            continue
        if not s:
            flush()
            i += 1
            continue
        h = re.match(r"^(#{1,6})\s+(.*?)\s*#*\s*$", s)
        if h:
            flush()
            n = len(h.group(1))
            out.append(f"<h{n}>{inline(h.group(2))}</h{n}>")
            i += 1
            continue
        if re.match(r"^([-*_])(\s*\1){2,}$", s):
            flush()
            out.append("<hr>")
            i += 1
            continue
        if s.startswith(">"):
            flush()
            q = []
            while i < len(lines) and lines[i].strip().startswith(">"):
                q.append(re.sub(r"^\s*>\s?", "", lines[i]))
                i += 1
            out.append("<blockquote>" + render("\n".join(q)) + "</blockquote>")
            continue
        if "|" in s and i + 1 < len(lines) and _TABLE_SEP.match(lines[i + 1]) and "-" in lines[i + 1]:
            flush()
            head = _cells(ln)
            i += 2
            rows = []
            while i < len(lines) and "|" in lines[i] and lines[i].strip():
                rows.append(_cells(lines[i]))
                i += 1
            t = "<table><thead><tr>" + "".join(f"<th>{inline(c)}</th>" for c in head) + "</tr></thead><tbody>"
            for r in rows:
                t += "<tr>" + "".join(f"<td>{inline(c)}</td>" for c in r) + "</tr>"
            out.append(t + "</tbody></table>")
            continue
        m = _LIST.match(ln)
        if m:
            flush()
            html_list, i = _render_list(lines, i, len(m.group(1).replace("\t", "    ")))
            out.append(html_list)
            continue
        para.append(ln)
        i += 1
    flush()
    return "\n".join(out)
