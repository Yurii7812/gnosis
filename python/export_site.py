#!/usr/bin/env python3
"""vault を、オフラインで読める静的サイト（HTML）と、通常の Markdown ビューアで読める索引に書き出す（UT06・HT01）。

  export_site.py ROOT OUTDIR [--include-private] [--title 題]

- 表示専用。HTML には編集機能も任意のローカルファイルを読む仕組みも入れない。外部 CDN も使わない。
  CSP で `default-src 'none'` とし、スクリプトは同じフォルダの search.js（全文検索）と、その索引 search-index.js だけ。
- `private: true` / `export: false` を front matter に書いたノートは、既定では書き出さない（--include-private で含める）。
  書き出さないノートへのリンクは文字だけにする。
- 本文が参照するローカルの添付（画像・PDF など）は、vault の中にあるものだけをコピーする（.. やシンボリックリンクで外へ出ない）。
- 出力先は、無い／空／前回の書き出し（.gnosis-export がある）のときだけ。それ以外は何も書かずに止まる。
- 本物の索引・ノートは書き換えない。派生物なので、いつでも作り直せる。
出力: ノートごとの HTML・index.html（一覧）・folgezettel.html と FOLGEZETTEL.md（番号表）・search.html + search.js + bridge.js（`\\A` に埋め込まれたときだけ働く）+
search-index.js・style.css。
"""
from __future__ import annotations

import html
import json
import urllib.parse
import os
import re
import shutil
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import folgezettel as fz  # noqa: E402
import gnosis_graph as gg  # noqa: E402
import graph_analysis  # noqa: E402
import export_views2  # noqa: E402
import mandala  # noqa: E402
import md_html  # noqa: E402
import tasks as taskmod  # noqa: E402
import note_format_v2 as nf  # noqa: E402

MARKER = ".gnosis-export"
CSP = "default-src 'none'; img-src 'self'; style-src 'self'; script-src 'self'; base-uri 'none'; form-action 'none'"
CSS = """body{font:16px/1.7 system-ui,sans-serif;max-width:46rem;margin:0 auto;padding:1rem;color:#222;background:#fff}
@media(prefers-color-scheme:dark){body{color:#ddd;background:#16181c}a{color:#8ab4f8}}
nav.rel{font-size:.9rem;border-top:1px solid #8884;margin-top:2rem;padding-top:.5rem}
nav.rel h2{font-size:.95rem;margin:.6rem 0 .2rem}nav.rel ul{margin:0;padding-left:1.2rem}
img{max-width:100%}table{border-collapse:collapse}td,th{border:1px solid #8886;padding:.2rem .5rem}
pre{overflow:auto;padding:.6rem;background:#8882}li.task{list-style:none;margin-left:-1.2rem}
.crumb{font-size:.85rem;opacity:.8}
#kinds label{display:inline-block;margin-right:.8rem;font-size:.85rem}.sw{display:inline-block;width:.8rem;height:.8rem;margin:0 .25rem;vertical-align:middle;border-radius:2px}
svg#g{width:100%;height:auto;border:1px solid #8886;margin-top:.5rem}
body.fz{max-width:78rem}#fz{display:grid;grid-template-columns:minmax(14rem,22rem) 1fr;gap:1rem}
#tree ul{list-style:none;margin:0;padding:0}.tr{display:flex;align-items:center}.tr.sel{background:#4a90d933;border-radius:4px}.tr.gap .lab{opacity:.6;border-style:dashed}
button{font:inherit;cursor:pointer}.tog{border:0;background:none;width:1.4rem;color:inherit}.lab,.chip{border:1px solid #8886;background:none;color:inherit;border-radius:4px;padding:.05rem .4rem;margin:.1rem}
.lab{border-color:transparent;text-align:left}.chip.gap{border-style:dashed;opacity:.7}.chip.now{background:#4a90d955}
.nav button.go{padding:.3rem .7rem;margin:.15rem;border:1px solid #8886;border-radius:6px;background:none;color:inherit}.nav button:disabled{opacity:.35;cursor:default}
#cur{font-size:1.25rem;font-weight:bold}#cur.gap{opacity:.7}.row{margin:.4rem 0}.row b{display:inline-block;min-width:5.5rem;font-size:.85rem;opacity:.8}
iframe#pv{width:100%;height:22rem;border:1px solid #8886;border-radius:6px;background:#fff}.none{opacity:.6;font-size:.85rem}
body.views{max-width:80rem}.toolbar{display:flex;gap:.6rem;flex-wrap:wrap;align-items:center;margin:.5rem 0}.toolbar input{padding:.3rem .5rem;min-width:14rem}
#cards{column-width:17rem;column-gap:1rem}.card{break-inside:avoid;border:1px solid #8886;border-radius:8px;padding:.6rem;margin:0 0 1rem;position:relative;background:#8881}
.card.pinned{border-color:#e0a800}.card img{width:100%;border-radius:6px}.card h3{margin:.3rem 0;font-size:1rem}.card p{margin:.3rem 0;font-size:.9rem;opacity:.9}
.card .meta{font-size:.75rem;opacity:.7}.card .pin{position:absolute;top:.3rem;right:.3rem;border:0;background:none;color:inherit;font-size:1.1rem;cursor:pointer}
.chip{font-size:.75rem;border:1px solid #8886;border-radius:4px;padding:0 .3rem}table.t{border-collapse:collapse;width:100%}table.t th,table.t td{border-bottom:1px solid #8884;padding:.25rem .5rem;text-align:left}
table.t td.num{text-align:right}.sortb{border:0;background:none;color:inherit;font:inherit;font-weight:bold;cursor:pointer}
#tl section{margin:1rem 0}#tl h2{font-size:1rem;margin:.2rem 0}#tl ul{list-style:none;padding-left:.5rem;border-left:3px solid #4a90d966}.tm{opacity:.6;font-size:.85rem}"""
JS = """(function(){var q=document.getElementById('q'),r=document.getElementById('r'),d=window.GNOSIS_INDEX||[];
function run(){var v=q.value.trim().toLowerCase();r.textContent='';if(!v)return;var n=0;
d.forEach(function(e){if(n<200&&(e.t.toLowerCase().indexOf(v)>=0||e.x.indexOf(v)>=0)){n++;
var li=document.createElement('li'),a=document.createElement('a');a.href=e.u;a.textContent=e.t;li.appendChild(a);r.appendChild(li)}})}
var m=/^#q=(.*)$/.exec(location.hash);if(m){try{q.value=decodeURIComponent(m[1])}catch(e){}}
q.addEventListener('input',run);run()})();"""


def _page(title: str, body: str, css_prefix: str = "", extra_head: str = "", csp: str = CSP, body_class: str = "", body_attrs: str = "") -> str:
    return ("<!doctype html>\n<html lang=\"ja\"><head><meta charset=\"utf-8\">"
            f"<meta http-equiv=\"Content-Security-Policy\" content=\"{csp}\">"
            "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">"
            f"<title>{html.escape(title)}</title><link rel=\"stylesheet\" href=\"{css_prefix}style.css\"><script src=\"{css_prefix}bridge.js\"></script>{extra_head}"
            f"</head><body{f' class=\"{body_class}\"' if body_class else ''}{f' {body_attrs}' if body_attrs else ''}>{body}</body></html>\n")


def _excerpt(body_lines: list[str], limit: int = 180) -> str:
    """カード・検索の抜粋: 見出し・関係のブロック・コードを除いた本文の最初の部分（記号とリンクの書き方は外す）。"""
    out, fence = [], False
    for ln in body_lines:
        t = ln.strip()
        if t.startswith(("```", "~~~")):
            fence = not fence
            continue
        if fence or not t or t.startswith("#") or t in (nf.BRANCH_GROUP_HEAD, nf.LEGACY_THIS_NOTE_GROUP_HEAD):
            continue
        t = re.sub(r"!\[[^\]]*\]\([^)]*\)", "", t)
        t = re.sub(r"\[((?:\\.|[^\]\\])*)\]\([^)]*\)", r"\1", t)
        t = re.sub(r"^[-*+]\s+(\[[ xX]\]\s*)?", "", t)
        t = re.sub(r"[*_`~>|]+", "", t).strip()
        if t:
            out.append(t)
        if sum(len(x) for x in out) >= limit:
            break
    return " ".join(out)[:limit]


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
    assets = Path(__file__).resolve().parent / "site_assets"
    copied: set[str] = set()
    index_rows = []
    search = []
    (out / "style.css").write_text(CSS + "\n" + mandala.MANDALA_CSS, encoding="utf-8")
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
            crumbs = ('<div class="crumb">' + " / ".join(parts + [html.escape(node.fz)])
                      + f' ・ <a href="{"../" * rel.count("/")}fznav.html#id={urllib.parse.quote(node.fz)}">番号ナビで見る</a></div>')
        kinds = [("parent_branch", "親（ParentBranch）"), ("group", "グループ"), ("context", "文脈"), ("related", "関連"), ("backlink", "バックリンク")]
        rel_html = ""
        for k, label in kinds:
            targets = sorted({e.dst for e in g.edges if e.src == rel and e.kind == k})
            if targets:
                rel_html += f"<h2>{label}</h2><ul>" + "".join(f"<li>{link_to(rel, t, g.nodes[t].title)}</li>" for t in targets) + "</ul>"
        incoming = sorted({e.src for e in g.edges if e.dst == rel and e.kind in ("link", "branch_group", "parent_branch", "group", "context", "related")})
        if incoming:
            rel_html += "<h2>このノートへのリンク</h2><ul>" + "".join(f"<li>{link_to(rel, t, g.nodes[t].title)}</li>" for t in incoming) + "</ul>"
        rel_nav = f'<nav class="rel">{rel_html}</nav>' if rel_html else ""
        up = "../" * rel.count("/")
        if mandala.is_mandala((root / rel).read_text(encoding="utf-8")):
            # 曼荼羅ノートは 9×9 の格子で見せる（表のマス以外の本文は、そのあとに通常どおり出す）
            main = f"<h1>{html.escape(node.title)}</h1>" + mandala.to_html(mandala.parse(body), node.title)
        else:
            main = md_html.render(body)
        page = _page(node.title, f'<p class="crumb"><a href="{up}index.html">一覧</a></p>{crumbs}' + main + rel_nav + f'<p class="crumb"><a href="{up}graph.html#n={urllib.parse.quote(rel)}&amp;depth=1">このノートの周りのグラフ</a></p>', up)
        dest = out / _out_name(rel)
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text(page, encoding="utf-8")
        index_rows.append((node.title, rel, node.fz))
        search.append({"u": _out_name(rel), "t": node.title, "x": re.sub(r"\s+", " ", body).lower()[:3000]})
    index_rows.sort(key=lambda r: (r[0].lower(), r[1]))
    items = "".join(f'<li><a href="{html.escape(_out_name(rel), quote=True)}">{html.escape(t)}</a>'
                    + (f' <small>({html.escape(f)})</small>' if f else "") + "</li>" for t, rel, f in index_rows)
    (out / "index.html").write_text(_page(title, f'<h1>{html.escape(title)}</h1><p><a href="folgezettel.html">番号の一覧（Folgezettel）</a> ・ '
                                         f'<a href="cards.html">カード</a> ・ <a href="table.html">テーブル</a> ・ <a href="timeline.html">タイムライン</a> ・ <a href="fznav.html">番号ナビ</a> ・ <a href="graph.html">グラフ</a> ・ <a href="analysis.html">分析</a> ・ <a href="views.html">そのほかのビュー</a> ・ <a href="search.html">検索</a></p><ul>{items}</ul>'), encoding="utf-8")
    (out / "search.html").write_text(_page("検索", '<h1>検索</h1><input id="q" type="search" placeholder="題や本文" autofocus>'
                                           '<ul id="r"></ul><script src="search-index.js"></script><script src="search.js"></script>'), encoding="utf-8")
    # ノート一覧のデータ（カード・テーブル・タイムライン）。書き出したノートだけ。派生データなので vault から作り直せる
    in_out: dict[str, list[int]] = {r: [0, 0] for r in notes}
    for e in g.edges:
        if e.derived or e.kind == "backlink" or e.src not in notes or e.dst not in notes:
            continue
        in_out[e.src][0] += 1
        in_out[e.dst][1] += 1
    meta = []
    for rel, d in notes.items():
        node = g.nodes[rel]
        text = (root / rel).read_text(encoding="utf-8")
        tm = next((ln.split(":", 1)[1].strip() for ln in d["fm"] if ln.startswith("time:")), "")
        img = ""
        m = re.search(r"!\[[^\]]*\]\(([^)\s]+)", "\n".join(d["body"]))
        if m and not re.match(r"^[A-Za-z][A-Za-z0-9+.-]*:", m.group(1)):
            cand = (root / rel).parent / m.group(1).split("#", 1)[0]
            try:
                real = cand.resolve(strict=True)
                real.relative_to(root)
                if (out / real.relative_to(root)).is_file():
                    img = real.relative_to(root).as_posix()
            except (OSError, ValueError):
                pass
        ts = taskmod.parse_text(text, rel)
        meta.append({"id": rel, "title": node.title, "fz": node.fz, "href": _out_name(rel), "time": tm,
                     "mtime": int((root / rel).stat().st_mtime), "excerpt": _excerpt(d["body"]), "image": img,
                     "out": in_out[rel][0], "in": in_out[rel][1], "size": len(text.encode("utf-8")),
                     "tasks_open": sum(1 for t in ts if not t.done), "tasks_done": sum(1 for t in ts if t.done),
                     "location": export_views2._fm_value(d["fm"], "location")})
    (out / "notes-data.js").write_text("window.GNOSIS_NOTES=" + json.dumps(meta, ensure_ascii=False) + ";\n", encoding="utf-8")
    for name in ("viewscore.js", "views.js"):
        shutil.copyfile(assets / name, out / name)
    tools = ('<div class="toolbar"><input id="q" type="search" placeholder="絞り込み（語を空白で区切る・-語で除外）" aria-label="絞り込み">{extra}<span id="count"></span></div>')
    nav = '<p class="crumb"><a href="index.html">一覧</a> ・ <a href="cards.html">カード</a> ・ <a href="table.html">テーブル</a> ・ <a href="timeline.html">タイムライン</a></p>'
    sorts = ('<select id="sort" aria-label="並べ替え"><option value="updated">更新日</option><option value="created">作成日</option><option value="title">題</option>'
             '<option value="fz">番号</option><option value="links_in">被リンク</option><option value="size">サイズ</option></select><button type="button" id="dir" class="chip">降順 ▼</button>')
    scripts = '<script src="notes-data.js"></script><script src="fznav-core.js"></script><script src="viewscore.js"></script><script src="views.js"></script>'
    (out / "cards.html").write_text(_page("カード", nav + "<h1>カード</h1>" + tools.format(extra=sorts) + '<div id="cards"></div>' + scripts, body_class="views", body_attrs='data-view="cards"'), encoding="utf-8")
    (out / "table.html").write_text(_page("テーブル", nav + "<h1>テーブル</h1>" + tools.format(extra="") + '<table id="tbl" class="t"></table>' + scripts, body_class="views", body_attrs='data-view="table"'), encoding="utf-8")
    (out / "timeline.html").write_text(_page("タイムライン", nav + "<h1>タイムライン</h1>" + tools.format(extra="") + '<div id="tl"></div>' + scripts, body_class="views", body_attrs='data-view="timeline"'), encoding="utf-8")
    # 分析ページ（書き出したノートだけで分析する。非公開は含めない）
    sub = gg.Graph(root=g.root, nodes={r: n for r, n in g.nodes.items() if r in notes},
                   edges=[e for e in g.edges if e.src in notes and e.dst in notes], broken=[])
    rep = graph_analysis.report(sub).replace("](", "](").replace(".md)", ".html)")
    (out / "analysis.html").write_text(_page("グラフ分析", '<p class="crumb"><a href="index.html">一覧</a> ・ <a href="graph.html">グラフ</a></p>' + md_html.render(rep)), encoding="utf-8")
    # グラフ表示（全体・ローカル）。書き出したノートだけを節点・辺にする（非公開ノートは節点にも辺にも出さない）
    shutil.copyfile(assets / "bridge.js", out / "bridge.js")
    for name in ("graphcore.js", "graph.js"):
        shutil.copyfile(assets / name, out / name)
    gdata = {"nodes": [{"id": r, "title": g.nodes[r].title, "fz": g.nodes[r].fz, "href": _out_name(r), "group": g.nodes[r].is_group} for r in notes],
             "edges": [{"s": e.src, "d": e.dst, "k": e.kind} for e in g.edges if e.src in notes and e.dst in notes]}
    (out / "graph-data.js").write_text("window.GNOSIS_GRAPH=" + json.dumps(gdata, ensure_ascii=False) + ";\n", encoding="utf-8")
    (out / "graph.html").write_text(_page("グラフ", '<p class="crumb"><a href="index.html">一覧</a></p><h1>グラフ</h1>'
        '<p>中心のノート: <select id="note"><option value="">（全体）</option></select> '
        '深さ: <select id="depth"><option>1</option><option>2</option><option>3</option><option>4</option><option>5</option></select></p>'
        '<div id="kinds"></div><p><label><input type="checkbox" id="labels"> 関係の名前を線の上に表示（コンセプトマップ）</label></p><p id="info"></p><svg id="g" viewBox="0 0 900 640" role="img" aria-label="ノートの関係グラフ"></svg>'
        '<script src="graph-data.js"></script><script src="graphcore.js"></script><script src="graph.js"></script>'), encoding="utf-8")
    # 追加ビュー（階層ツリー・Treemap・カンバン・マインドマップ ほか）。graph-data.js が書かれたあと
    export_views2.write(out, root, g, notes, copied, assets, _page, _out_name)
    # Folgezettel 番号ナビゲーター（番号のついた書き出し済みノート。本文プレビュー付き）
    for name in ("fznav-core.js", "fznav.js"):
        shutil.copyfile(assets / name, out / name)
    fzitems = [{"id": n.fz, "files": [_out_name(r)], "title": n.title} for r, n in g.nodes.items()
               if r in notes and n.fz and fz.ID_RE.fullmatch(n.fz) and not n.is_group]
    # ブランチで作ったグループは親ノートと同じ番号を持つ。同じ番号のノートがあればそちらを優先する
    have = {i["id"] for i in fzitems}
    for r, n in g.nodes.items():
        if r in notes and n.fz and fz.ID_RE.fullmatch(n.fz) and n.is_group and n.fz not in have:
            have.add(n.fz)
            fzitems.append({"id": n.fz, "files": [_out_name(r)], "title": n.title})
    (out / "fz-data.js").write_text("window.GNOSIS_FZ=" + json.dumps(fzitems, ensure_ascii=False) + ";\n", encoding="utf-8")
    FZ_CSP = CSP + "; frame-src 'self'"
    (out / "fznav.html").write_text(_page("Folgezettel ナビ", """<p class="crumb"><a href="index.html">一覧</a> ・ <a href="folgezettel.html">番号の表</a> ・ <a href="graph.html">グラフ</a></p>
<h1>Folgezettel ナビ</h1>
<p class="none">キー: ↑ 親 ・ ↓ 最初の子 ・ ← → 兄弟 ・ [ ] 番号順の前後 ・ Home End 最初と最後 ・ Alt+← → 履歴</p>
<div id="fz"><div><p><button type="button" id="b-allopen" class="chip">すべて開く</button><button type="button" id="b-allclose" class="chip">すべて閉じる</button></p><div id="tree"></div></div>
<div class="nav"><div id="cur"></div><div id="crumbs" class="row"></div>
<div class="row"><button type="button" class="go" id="b-up">↑ 親</button><button type="button" class="go" id="b-down">↓ 最初の子</button><button type="button" class="go" id="b-prev">← 前の兄弟</button><button type="button" class="go" id="b-next">次の兄弟 →</button>
<button type="button" class="go" id="b-oprev">[ 番号順で前</button><button type="button" class="go" id="b-onext">番号順で次 ]</button><button type="button" class="go" id="b-first">最初</button><button type="button" class="go" id="b-last">最後</button></div>
<div class="row"><b>親</b><span id="parent"></span></div><div class="row"><b>兄弟</b><span id="siblings"></span></div><div class="row"><b>子</b><span id="children"></span></div>
<div class="row"><b>たどった順</b><button type="button" class="chip" id="b-back">◀ 戻る</button><button type="button" class="chip" id="b-fwd">進む ▶</button> <span id="trail"></span></div>
<p><a id="open" href="#">ノートを開く</a></p><iframe id="pv" title="ノートのプレビュー" sandbox="allow-same-origin"></iframe></div></div>
<script src="fz-data.js"></script><script src="fznav-core.js"></script><script src="fznav.js"></script>""", csp=FZ_CSP, body_class="fz"), encoding="utf-8")
    # fetch() はファイルとして直接開いたとき（file://）に使えないので、索引は <script src> で読む JS にする
    (out / "search-index.js").write_text("window.GNOSIS_INDEX=" + json.dumps(search, ensure_ascii=False) + ";\n", encoding="utf-8")

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
