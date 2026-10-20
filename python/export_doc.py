#!/usr/bin/env python3
"""vault（または 1 つのノートとその枝）を、1 冊の電子書籍・文書に書き出す（UT07）。EPUB・単一 HTML・PDF。

  export_doc.py ROOT epub OUT.epub [--title 題] [--root ノート] [--include-private]
  export_doc.py ROOT html OUT.html [同上]            1 つの HTML ファイル（ブラウザで印刷・PDF 保存にも使える）
  export_doc.py ROOT pdf  OUT.pdf  [同上]            単一 HTML を headless のブラウザで PDF にする（下の注意）

- 章の順は Folgezettel の番号順（番号のないノートは題の順で最後）。`--root` を付けると、そのノートと番号の下にある枝だけ。
- `private: true` / `export: false` のノートは含めない（`--include-private` で含める）。含めないノートへのリンクは文字だけにする。
- 本文が参照する vault の中の画像だけを持っていく（.. やシンボリックリンクで外へ出ない・ドット始まりは除く）。
- 出力先は**まだ無いファイル**だけ（上書きしない）。vault の中へは書かない。ノートは読むだけ。
- EPUB は標準の `zipfile` だけで作る（外部ツール不要）。各章は XHTML として読める形にする。
- PDF は、この PC にある headless 対応のブラウザ（環境変数 `GNOSIS_CHROME`、または chromium / google-chrome / brave-browser /
  chrome-headless-shell）に頼る。見つからなければ、そう伝えて何も作らない（自前で PDF は組まない）。
"""
from __future__ import annotations

import datetime as dt
import html
import json
import mimetypes
import os
import posixpath
import re
import shutil
import subprocess
import sys
import tempfile
import uuid
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import export_site  # noqa: E402
import folgezettel as fz  # noqa: E402
import gnosis_graph as gg  # noqa: E402
import md_html  # noqa: E402
import note_format_v2 as nf  # noqa: E402

CSS = """body{font-family:serif;line-height:1.7;margin:1em}h1,h2,h3{font-family:sans-serif}img{max-width:100%}pre{white-space:pre-wrap;background:#eee;padding:.5em}
table{border-collapse:collapse}td,th{border:1px solid #888;padding:.2em .5em}blockquote{border-left:3px solid #999;margin-left:0;padding-left:1em;color:#444}
.chapter{page-break-before:always}.crumb{font-size:.8em;color:#666}"""
VOID = re.compile(r"<(br|hr|img|input|meta|link)([^>]*?)\s*/?>", re.I)


def _xhtml(fragment: str) -> str:
    """md_html の出力（HTML5）を、XML として読める形にする（空要素を閉じる）。"""
    return VOID.sub(lambda m: f"<{m.group(1)}{m.group(2)}/>", fragment)


def _is_under(ident: str, ancestor: str) -> bool:
    """番号 ident が、番号 ancestor の下（子・孫…）にあるか。"""
    cur = fz.parent_id(ident) if ident else ""
    while cur:
        if cur == ancestor:
            return True
        cur = fz.parent_id(cur)
    return False


def _chapters(root: Path, start: str | None, include_private: bool) -> tuple[gg.Graph, list[str], dict[str, dict]]:
    g = gg.build(root)
    notes: dict[str, dict] = {}
    for rel, node in g.nodes.items():
        text = (root / rel).read_text(encoding="utf-8")
        d = nf._simple_parse_text(root / rel, text)
        if not include_private and (export_site._fm_flag(d["fm"], "private", "true") or export_site._fm_flag(d["fm"], "export", "false")):
            continue
        notes[rel] = d
    order = sorted(notes, key=lambda r: (g.nodes[r].fz == "", fz.natural_key(g.nodes[r].fz) if g.nodes[r].fz else (), g.nodes[r].title, r))
    if start:
        key = next((r for r in notes if r == start or Path(r).name == start or Path(r).stem == start or g.nodes[r].title == start), None)
        if key is None:
            raise ValueError("起点のノートが見つかりません: " + start)
        f = g.nodes[key].fz
        order = [r for r in order if r == key or (f and _is_under(g.nodes[r].fz, f))] if f else [key]
    return g, order, notes


def _check_out(root: Path, out: Path) -> Path:
    out = out.resolve()
    if out == root or root in out.parents:
        raise ValueError("出力先を vault の中にはできません: " + str(out))
    if out.exists():
        raise ValueError("すでにあります（上書きしません）: " + str(out))
    if not out.parent.is_dir():
        raise ValueError("出力先のフォルダがありません: " + str(out.parent))
    return out


def _render_chapters(root: Path, g: gg.Graph, order: list[str], notes: dict[str, dict], name_of, link_ext: str) -> tuple[list[dict], dict[str, str]]:
    """章ごとの HTML。images: 持っていく画像（vault 相対 → 本の中のパス）。"""
    images: dict[str, str] = {}
    chapters = []
    for rel in order:
        d = notes[rel]
        body_lines = ["## 子ノート" if ln.strip() in (nf.BRANCH_GROUP_HEAD, nf.LEGACY_THIS_NOTE_GROUP_HEAD) else ln for ln in d["body"]]
        first = next((i for i, ln in enumerate(body_lines) if ln.strip()), None)
        if first is not None and body_lines[first].strip() == "# " + g.nodes[rel].title:       # 章の見出しは書き出し側で付けるので、本文先頭の同じ題は重ねない
            del body_lines[first]
        body = export_site._plain_unexported_links("\n".join(body_lines), rel, {r: None for r in order})
        # 画像のパスを、本の中のパスへ。vault の中にあるものだけ
        def img(m):
            alt, url = m.group(1), m.group(2).split(" ", 1)[0]
            if re.match(r"^[A-Za-z][A-Za-z0-9+.-]*:", url) or url.startswith(("#", "/")):
                return m.group(0)
            src = (root / rel).parent / url.split("#", 1)[0]
            try:
                real = src.resolve(strict=True)
                real.relative_to(root)
            except (OSError, ValueError):
                return alt
            if not real.is_file() or any(p.startswith(".") for p in real.relative_to(root).parts):
                return alt
            key = real.relative_to(root).as_posix()
            images.setdefault(key, "images/" + f"{len(images) + 1}{real.suffix.lower()}")
            return f"![{alt}]({images[key]})"
        body = re.sub(r"!\[((?:\\.|[^\]\\])*)\]\(([^)]+)\)", img, body)
        h = md_html.render(body)
        # 画像は章の場所（chapters/）から見て ../images/…。ノート間リンク（相対 .html）は章のファイル名へ
        h = h.replace('src="images/', 'src="../images/')
        def href(m):
            val = m.group(1)
            if re.match(r"^[A-Za-z][A-Za-z0-9+.-]*:", val) or val.startswith("#"):
                return m.group(0)
            path, sep, frag = val.partition("#")
            if path.lower().endswith(".html"):
                tgt = posixpath.normpath(posixpath.join(posixpath.dirname(rel), path[:-5] + ".md"))
                if tgt in order:
                    return f'href="{name_of(tgt)}{sep}{frag}"'
            return m.group(0)
        h = re.sub(r'href="([^"]*)"', href, h)
        chapters.append({"rel": rel, "title": g.nodes[rel].title, "fz": g.nodes[rel].fz, "html": h})
    return chapters, images


def build_html(root: str | Path, out: str | Path, title: str = "Gnosis", start: str | None = None, include_private: bool = False) -> dict:
    root = Path(root).resolve()
    out = _check_out(root, Path(out))
    g, order, notes = _chapters(root, start, include_private)
    if not order:
        raise ValueError("書き出すノートがありません")
    anchors = {r: f"ch{i}" for i, r in enumerate(order, 1)}
    chapters, images = _render_chapters(root, g, order, notes, lambda r: "#" + anchors[r], ".html")
    # 単一 HTML: 画像は data URL にして埋め込む（ファイル 1 つで完結する。大きすぎる画像は省く）
    import base64
    data_url: dict[str, str] = {}
    for key, dest in images.items():
        data = (root / key).read_bytes()
        if len(data) <= 2_000_000:
            data_url["../" + dest] = f"data:{mimetypes.guess_type(key)[0] or 'application/octet-stream'};base64,{base64.b64encode(data).decode()}"

    def embed(h: str) -> str:
        return re.sub(r'src="(\.\./images/[^"]+)"', lambda m: f'src="{data_url[m.group(1)]}"' if m.group(1) in data_url else 'alt="（大きすぎる画像は省きました）"', h)

    parts = []
    for c in chapters:
        parts.append(f'<section class="chapter" id="{anchors[c["rel"]]}"><h1>{html.escape((c["fz"] + " ") if c["fz"] else "")}{html.escape(c["title"])}</h1>{embed(c["html"])}</section>')
    toc = "".join(f'<li><a href="#{anchors[c["rel"]]}">{html.escape(c["title"])}</a></li>' for c in chapters)
    doc = ("<!doctype html>\n<html lang=\"ja\"><head><meta charset=\"utf-8\">"
           "<meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; img-src data:; style-src 'unsafe-inline'\">"
           f"<title>{html.escape(title)}</title><style>{CSS}</style></head><body><h1>{html.escape(title)}</h1><nav><h2>目次</h2><ol>{toc}</ol></nav>{''.join(parts)}</body></html>\n")
    out.write_text(doc, encoding="utf-8")
    return {"path": str(out), "chapters": len(chapters), "images": len(images)}


def build_epub(root: str | Path, out: str | Path, title: str = "Gnosis", start: str | None = None, include_private: bool = False,
               now: dt.datetime | None = None) -> dict:
    root = Path(root).resolve()
    out = _check_out(root, Path(out))
    g, order, notes = _chapters(root, start, include_private)
    if not order:
        raise ValueError("書き出すノートがありません")
    files = {r: f"chapters/c{i:03d}.xhtml" for i, r in enumerate(order, 1)}
    chapters, images = _render_chapters(root, g, order, notes, lambda r: posixpath.basename(files[r]), ".xhtml")
    now = now or dt.datetime.now(dt.timezone.utc)
    uid = "urn:uuid:" + str(uuid.uuid5(uuid.NAMESPACE_URL, "gnosis:" + title + ":" + ",".join(order)))
    def xdoc(t: str, body: str, css_href: str) -> str:
        return ('<?xml version="1.0" encoding="utf-8"?>\n<!DOCTYPE html>\n<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" lang="ja" xml:lang="ja">'
                f'<head><meta charset="utf-8"/><title>{html.escape(t)}</title><link rel="stylesheet" type="text/css" href="{css_href}"/></head><body>{body}</body></html>\n')
    entries: dict[str, bytes] = {}
    for c in chapters:
        head = f"<h1>{html.escape((c['fz'] + ' ') if c['fz'] else '')}{html.escape(c['title'])}</h1>"
        entries["OEBPS/" + files[c["rel"]]] = xdoc(c["title"], head + _xhtml(c["html"]), "../style.css").encode("utf-8")
    nav_items = "".join(f'<li><a href="{files[c["rel"]]}">{html.escape(c["title"])}</a></li>' for c in chapters)
    entries["OEBPS/nav.xhtml"] = xdoc("目次", f'<nav epub:type="toc" id="toc"><h1>目次</h1><ol>{nav_items}</ol></nav>', "style.css").encode("utf-8")
    entries["OEBPS/style.css"] = CSS.encode("utf-8")
    manifest = ['<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>', '<item id="css" href="style.css" media-type="text/css"/>']
    spine = []
    for i, c in enumerate(chapters, 1):
        manifest.append(f'<item id="c{i:03d}" href="{files[c["rel"]]}" media-type="application/xhtml+xml"/>')
        spine.append(f'<itemref idref="c{i:03d}"/>')
    for key, dest in images.items():
        mt = mimetypes.guess_type(key)[0] or "application/octet-stream"
        entries["OEBPS/" + dest] = (root / key).read_bytes()
        manifest.append(f'<item id="img{len(manifest)}" href="{dest}" media-type="{mt}"/>')
    opf = ('<?xml version="1.0" encoding="utf-8"?>\n<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="bookid" xml:lang="ja">'
           f'<metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="bookid">{uid}</dc:identifier><dc:title>{html.escape(title)}</dc:title><dc:language>ja</dc:language>'
           f'<meta property="dcterms:modified">{now:%Y-%m-%dT%H:%M:%SZ}</meta></metadata><manifest>{"".join(manifest)}</manifest><spine>{"".join(spine)}</spine></package>\n')
    entries["OEBPS/content.opf"] = opf.encode("utf-8")
    container = ('<?xml version="1.0" encoding="UTF-8"?>\n<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
                 '<rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>\n')
    tmp = out.with_name(out.name + ".tmp")
    with zipfile.ZipFile(tmp, "w") as z:
        z.writestr(zipfile.ZipInfo("mimetype", (1980, 1, 1, 0, 0, 0)), "application/epub+zip", compress_type=zipfile.ZIP_STORED)   # 先頭・無圧縮（EPUB の決まり）
        z.writestr("META-INF/container.xml", container, compress_type=zipfile.ZIP_DEFLATED)
        for name, data in entries.items():
            z.writestr(name, data, compress_type=zipfile.ZIP_DEFLATED)
    os.replace(tmp, out)
    return {"path": str(out), "chapters": len(chapters), "images": len(images)}


def find_browser() -> str | None:
    env = os.environ.get("GNOSIS_CHROME")
    if env and shutil.which(env) or (env and Path(env).is_file()):
        return env
    for name in ("chromium", "chromium-browser", "google-chrome", "google-chrome-stable", "brave-browser", "brave", "chrome-headless-shell"):
        p = shutil.which(name)
        if p:
            return p
    return None


def build_pdf(root: str | Path, out: str | Path, title: str = "Gnosis", start: str | None = None, include_private: bool = False) -> dict:
    out = Path(out)
    exe = find_browser()
    if not exe:
        raise ValueError("PDF にするための headless 対応のブラウザ（chromium / google-chrome / brave など）が見つかりません。"
                         "環境変数 GNOSIS_CHROME で指定するか、単一 HTML を書き出して、ブラウザの印刷から PDF にしてください")
    root = Path(root).resolve()
    final = _check_out(root, out)
    with tempfile.TemporaryDirectory() as td:
        tmp_html = Path(td) / "book.html"
        info = build_html(root, tmp_html, title, start, include_private)
        tmp_pdf = Path(td) / "book.pdf"
        r = subprocess.run([exe, "--headless", "--no-sandbox", "--disable-gpu", "--no-pdf-header-footer", f"--print-to-pdf={tmp_pdf}", tmp_html.as_uri()],
                           capture_output=True, text=True, timeout=180)
        if not tmp_pdf.is_file() or tmp_pdf.stat().st_size < 200 or tmp_pdf.read_bytes()[:5] != b"%PDF-":
            raise ValueError("PDF を作れませんでした: " + (r.stderr or r.stdout or "")[-200:])
        shutil.copyfile(tmp_pdf, final)
    return {"path": str(final), "chapters": info["chapters"], "images": info["images"], "browser": exe}


def main(argv: list[str]) -> int:
    try:
        opts, a, it = {}, [], iter(argv)
        for x in it:
            if x in ("--title", "--root"):
                opts[x[2:]] = next(it)
            elif x == "--include-private":
                opts["private"] = True
            else:
                a.append(x)
        if len(a) != 3 or a[1] not in ("epub", "html", "pdf"):
            print(__doc__, file=sys.stderr)
            return 2
        fn = {"epub": build_epub, "html": build_html, "pdf": build_pdf}[a[1]]
        r = fn(a[0], a[2], opts.get("title", "Gnosis"), opts.get("root"), opts.get("private", False))
        print(json.dumps(r, ensure_ascii=False))
    except (OSError, ValueError, StopIteration, subprocess.TimeoutExpired) as e:
        print(json.dumps({"error": str(e)}, ensure_ascii=False))
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
