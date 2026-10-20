#!/usr/bin/env python3
"""vault を、オフラインで読める静的サイト（HTML）と、通常の Markdown ビューアで読める索引に書き出す（UT06・HT01）。

  export_site.py ROOT OUTDIR [--include-private] [--title 題]

- 表示専用。HTML には編集機能も任意のローカルファイルを読む仕組みも入れない。外部 CDN も使わない。
  CSP で `default-src 'none'` とし、スクリプトは同じフォルダの search.js（全文検索）だけ。
- `private: true` / `export: false` を front matter に書いたノートは、既定では書き出さない（--include-private で含める）。
  書き出さないノートへのリンクは文字だけにする。
- 本文が参照するローカルの添付（画像・PDF など）は、vault の中にあるものだけをコピーする（.. やシンボリックリンクで外へ出ない）。
- 出力先は、無い／空／前回の書き出し（.gnosis-export がある）のときだけ。それ以外は何も書かずに止まる。
- 本物の索引・ノートは書き換えない。派生物なので、いつでも作り直せる。
出力: ノートごとの HTML・index.html（一覧）・folgezettel.html と FOLGEZETTEL.md（番号表）・search.html + search.js +
search-index.json・style.css。
"""
from __future__ import annotations

import html
import json
import os
import re
import shutil
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import folgezettel as fz  # noqa: E402
import gnosis_graph as gg  # noqa: E402
import md_html  # noqa: E402
import note_format_v2 as nf  # noqa: E402

MARKER = ".gnosis-export"
CSP = "default-src 'none'; img-src 'self'; style-src 'self'; script-src 'self'; base-uri 'none'; form-action 'none'"
CSS = """body{font:16px/1.7 system-ui,sans-serif;max-width:46rem;margin:0 auto;padding:1rem;color:#222;background:#fff}
@media(prefers-color-scheme:dark){body{color:#ddd;background:#16181c}a{color:#8ab4f8}}
nav.rel{font-size:.9rem;border-top:1px solid #8884;margin-top:2rem;padding-top:.5rem}
nav.rel h2{font-size:.95rem;margin:.6rem 0 .2rem}nav.rel ul{margin:0;padding-left:1.2rem}
img{max-width:100%}table{border-collapse:collapse}td,th{border:1px solid #8886;padding:.2rem .5rem}
pre{overflow:auto;padding:.6rem;background:#8882}li.task{list-style:none;margin-left:-1.2rem}
.crumb{font-size:.85rem;opacity:.8}"""
JS = """(function(){var q=document.getElementById('q'),r=document.getElementById('r'),idx=null;
function load(){return idx?Promise.resolve(idx):fetch('search-index.json').then(function(x){return x.json()}).then(function(j){idx=j;return j})}
function run(){var v=q.value.trim().toLowerCase();r.textContent='';if(!v)return;load().then(function(d){
var n=0;d.forEach(function(e){if(n<200&&(e.t.toLowerCase().indexOf(v)>=0||e.x.indexOf(v)>=0)){n++;
var li=document.createElement('li'),a=document.createElement('a');a.href=e.u;a.textContent=e.t;li.appendChild(a);r.appendChild(li)}})})}
q.addEventListener('input',run);run()})();"""


def _page(title: str, body: str, css_prefix: str = "", extra_head: str = "") -> str:
    return ("<!doctype html>\n<html lang=\"ja\"><head><meta charset=\"utf-8\">"
            f"<meta http-equiv=\"Content-Security-Policy\" content=\"{CSP}\">"
            "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">"
            f"<title>{html.escape(title)}</title><link rel=\"stylesheet\" href=\"{css_prefix}style.css\">{extra_head}"
            f"</head><body>{body}</body></html>\n")


def _out_name(rel: str) -> str:
    return rel[:-3] + ".html" if rel.endswith(".md") else rel


def _fm_flag(fm: list[str], key: str, value: str) -> bool:
    return any(re.match(rf"^{key}:\s*{value}\s*$", ln, re.I) for ln in fm)


def _prepare_out(out: Path, root: Path) -> None:
    out = out.resolve()
    if out == root or root in out.parents and not any(p.startswith(".") for p in out.relative_to(root).parts):
        raise ValueError("出力先は vault の外か、ドット始まりのフォルダにしてください（書き出しをノートとして読み直さないため）")
    if out.exists():
        if not out.is_dir():
            raise ValueError("出力先がフォルダではありません: " + str(out))
        if any(out.iterdir()) and not (out / MARKER).exists():
            raise ValueError("出力先が空でなく、前回の書き出しでもありません（何も書きません）: " + str(out))
    out.mkdir(parents=True, exist_ok=True)
    (out / MARKER).write_text("gnosis export\n", encoding="utf-8")


_MD_LINK = re.compile(r"(?<!!)\[((?:\\.|[^\]\\])*)\]\(([^)\s]+)(?:\s+\"[^\"]*\")?\)")


def _plain_unexported_links(body: str, rel: str, notes: dict) -> str:
    """書き出さないノート（非公開・存在しない）へのリンクは、文字だけにする（存在しないページへのリンクと、その名前を残さない）。"""
    def fix(m):
        url = m.group(2)
        if re.match(r"^[A-Za-z][A-Za-z0-9+.-]*:", url) or url.startswith("#"):
            return m.group(0)
        path = url.split("#", 1)[0]
        if not path.lower().endswith(".md"):
            return m.group(0)
        target = os.path.normpath(os.path.join(os.path.dirname(rel), path)).replace(os.sep, "/")
        return m.group(0) if target in notes else m.group(1)
    return _MD_LINK.sub(fix, body)


def export(root: str | Path, out: str | Path, include_private: bool = False, title: str = "Gnosis") -> dict:
    root = Path(root).resolve()
    out = Path(out)
    _prepare_out(out, root)
    out = out.resolve()
    g = gg.build(root)
    skipped: list[str] = []
    notes: dict[str, dict] = {}
    for rel, node in g.nodes.items():
        text = (root / rel).read_text(encoding="utf-8")
        d = nf._simple_parse_text(root / rel, text)
        if not include_private and (_fm_flag(d["fm"], "private", "true") or _fm_flag(d["fm"], "export", "false")):
            skipped.append(rel)
            continue
        notes[rel] = d
    copied: set[str] = set()
    index_rows = []
    search = []
    (out / "style.css").write_text(CSS, encoding="utf-8")
    (out / "search.js").write_text(JS, encoding="utf-8")

    def link_to(src_rel: str, dst_rel: str, label: str) -> str:
        if dst_rel in notes:
            href = os.path.relpath(_out_name(dst_rel), start=os.path.dirname(_out_name(src_rel)) or ".").replace(os.sep, "/")
            return f'<a href="{html.escape(href, quote=True)}">{html.escape(label)}</a>'
        return html.escape(label)

    def copy_assets(rel: str, body: str) -> None:
        for m in re.finditer(r"!?\[[^\]]*\]\(([^)\s]+)", body):
            url = m.group(1)
            if re.match(r"^[A-Za-z][A-Za-z0-9+.-]*:", url) or url.startswith(("#", "/")) or url.lower().split("#")[0].endswith(".md"):
                continue
            src = (root / rel).parent / url.split("#", 1)[0]
            try:
                real = src.resolve(strict=True)
                real.relative_to(root)  # vault の外へ出るもの（.. ・シンボリックリンク）は持ち出さない
            except (OSError, ValueError):
                continue
            if not real.is_file() or any(p.startswith(".") for p in real.relative_to(root).parts):
                continue
            dest = out / real.relative_to(root)
            if str(real) not in copied:
                dest.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(real, dest)
                copied.add(str(real))

    for rel, d in notes.items():
        node = g.nodes[rel]
        body_lines = []
        for ln in d["body"]:
            body_lines.append("## 子ノート（BranchGroup）" if ln.strip() in (nf.BRANCH_GROUP_HEAD, nf.LEGACY_THIS_NOTE_GROUP_HEAD) else ln)
        body = "\n".join(body_lines)
        body = _plain_unexported_links(body, rel, notes)
        copy_assets(rel, body)
        crumbs = ""
        if node.fz:
            cur, parts = fz.parent_id(node.fz), []
            info = g.fz_info(node.fz)
            for b in info["breadcrumbs"]:
                if b["exists"] and b["files"] and b["files"][0] in notes:
                    parts.append(link_to(rel, b["files"][0], b["id"]))
                else:
                    parts.append(html.escape(b["id"]))
            crumbs = '<div class="crumb">' + " / ".join(parts + [html.escape(node.fz)]) + "</div>"
        kinds = [("parent_branch", "親（ParentBranch）"), ("group", "グループ"), ("context", "文脈"), ("related", "関連"), ("backlink", "バックリンク")]
        rel_html = ""
        for k, label in kinds:
            targets = sorted({e.dst for e in g.edges if e.src == rel and e.kind == k})
            if targets:
                rel_html += f"<h2>{label}</h2><ul>" + "".join(f"<li>{link_to(rel, t, g.nodes[t].title)}</li>" for t in targets) + "</ul>"
        incoming = sorted({e.src for e in g.edges if e.dst == rel and e.kind in ("link", "branch_group")})
        if incoming:
            rel_html += "<h2>このノートへのリンク</h2><ul>" + "".join(f"<li>{link_to(rel, t, g.nodes[t].title)}</li>" for t in incoming) + "</ul>"
        rel_nav = f'<nav class="rel">{rel_html}</nav>' if rel_html else ""
        up = "../" * rel.count("/")
        page = _page(node.title, f'<p class="crumb"><a href="{up}index.html">一覧</a></p>{crumbs}' + md_html.render(body) + rel_nav, up)
        dest = out / _out_name(rel)
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text(page, encoding="utf-8")
        index_rows.append((node.title, rel, node.fz))
        search.append({"u": _out_name(rel), "t": node.title, "x": re.sub(r"\s+", " ", body).lower()[:3000]})
    index_rows.sort(key=lambda r: (r[0].lower(), r[1]))
    items = "".join(f'<li><a href="{html.escape(_out_name(rel), quote=True)}">{html.escape(t)}</a>'
                    + (f' <small>({html.escape(f)})</small>' if f else "") + "</li>" for t, rel, f in index_rows)
    (out / "index.html").write_text(_page(title, f'<h1>{html.escape(title)}</h1><p><a href="folgezettel.html">番号の一覧（Folgezettel）</a> ・ '
                                         f'<a href="search.html">検索</a></p><ul>{items}</ul>'), encoding="utf-8")
    (out / "search.html").write_text(_page("検索", '<h1>検索</h1><input id="q" type="search" placeholder="題や本文" autofocus>'
                                           '<ul id="r"></ul><script src="search.js"></script>'), encoding="utf-8")
    (out / "search-index.json").write_text(json.dumps(search, ensure_ascii=False), encoding="utf-8")

    # Folgezettel の番号表: 通常の Markdown ビューアで読める版と HTML 版（同じデータから作る）
    rows = []
    def walk(nodes, depth):
        for n in nodes:
            f = next((x for x in n["files"] if x in notes), None)
            rows.append((depth, n["id"], n["title"], f))
            walk(n["children"], depth + 1)
    walk(g.fz_tree(), 0)
    md = ["# Folgezettel（番号の一覧）", "", "| 番号 | 題 |", "|---|---|"]
    for depth, i, t, f in rows:
        label = ("　" * depth) + i
        md.append(f"| {label} | " + (f"[{t.replace('|', '/')}]({f.replace(' ', '%20')})" if f else t.replace("|", "/")) + " |")
    (out / "FOLGEZETTEL.md").write_text("\n".join(md) + "\n", encoding="utf-8")
    trs = "".join(f"<tr><td>{html.escape('　' * depth + i)}</td><td>"
                  + (f'<a href="{html.escape(_out_name(f), quote=True)}">{html.escape(t)}</a>' if f else html.escape(t)) + "</td></tr>"
                  for depth, i, t, f in rows)
    (out / "folgezettel.html").write_text(_page("Folgezettel", f"<h1>Folgezettel（番号の一覧）</h1><p><a href=\"index.html\">一覧へ</a></p>"
                                                 f"<table><thead><tr><th>番号</th><th>題</th></tr></thead><tbody>{trs}</tbody></table>"), encoding="utf-8")
    return {"notes": len(notes), "skipped_private": skipped, "assets": len(copied), "out": str(out)}


def main(argv: list[str]) -> int:
    args = [a for a in argv if not a.startswith("--")]
    title = "Gnosis"
    if "--title" in argv:
        title = argv[argv.index("--title") + 1]
        args = [a for a in args if a != title]
    if len(args) != 2:
        print(__doc__, file=sys.stderr)
        return 2
    try:
        print(json.dumps(export(args[0], args[1], "--include-private" in argv, title), ensure_ascii=False))
    except (OSError, ValueError) as e:
        print(json.dumps({"error": str(e)}, ensure_ascii=False))
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
