#!/usr/bin/env python3
"""静的サイトの追加ビュー（VW05〜VW24）のデータとページを書き出す。export_site.export から呼ぶ。

ページ（すべて表示専用・外部通信なし・CDN なし）: tree 階層ツリー / orphans 孤立・未参照・未索引 / matrix 隣接行列 / treemap / sunburst /
kanban カンバン / mindmap / growth 成長 / river 川 / compare 比較 / sankey / map 地図 / graph3d / slides / whiteboard / gallery、
それらの入口 views.html。

データは書き出したノートだけから作る（非公開ノートの題・本文・リンクを含めない）:
  tasks-data.js   Markdown のタスク（📅 期限など）。カンバン用
  files-data.js   コピーした添付（画像・PDF・音声・動画・その他）と、それを参照しているノート。ギャラリー用
  slides-data.js  front matter に `slides: true` を書いたノートだけ。`---` または `## ` で区切ったスライドを、安全な HTML にしたもの
  位置情報        front matter の `location: 緯度, 経度` を notes-data.js の location に載せる（export_site 側）
"""
from __future__ import annotations

import html
import json
import os
import posixpath
import re
import shutil
from pathlib import Path

import md_html
import tasks as taskmod

VIEWS = [
    ("tree", "階層ツリー", "ブランチ・グループ・番号による関係の階層（フォルダではありません）", "tree"),
    ("mindmap", "マインドマップ", "選んだノートを中心に、枝を放射状に広げる", "mindmap"),
    ("sunburst", "Sunburst", "階層を同心円で見る。弧の大きさは葉の数", "sunburst"),
    ("treemap", "Treemap", "番号の最上位ごとのまとまりと、ノートの大きさ", "treemap"),
    ("matrix", "隣接行列", "つながりの多いノートどうしの関係を表で見る", "matrix"),
    ("sankey", "Sankey", "番号の枝から枝への関係の流れ", "sankey"),
    ("compare", "比較", "2 つのノートのつながりの共通点と違い", "compare"),
    ("orphans", "孤立・未参照・未索引", "つながりのないノート、参照されないノート、索引に載っていないノート", "orphans"),
    ("kanban", "カンバン", "Markdown のタスクを期限ごとの列で（表示専用）", "kanban"),
    ("growth", "成長", "月ごとの新しいノートの数と累計", "growth"),
    ("river", "ストーリーリバー", "番号の枝ごとの流れを時間に沿って", "river"),
    ("map", "地図", "front matter の location: 緯度, 経度 があるノート（地図の画像は使いません）", "map"),
    ("graph3d", "3D グラフ", "回転できる立体のグラフ（任意。使えなくても他のビューは使えます）", "graph3d"),
    ("slides", "スライド", "front matter に slides: true を書いたノートを 1 枚ずつ", "slides"),
    ("whiteboard", "ホワイトボード", "ノートのカードを自由に並べる（位置はこのブラウザだけに覚える）", "whiteboard"),
    ("gallery", "ギャラリー", "画像・PDF などの添付と、それを参照しているノート", "gallery"),
]
NAV_LINKS = " ・ ".join(f'<a href="{v[0]}.html">{html.escape(v[1])}</a>' for v in VIEWS)

STYLE = """body.v2{max-width:84rem}.v2 .bar{display:flex;gap:.6rem;flex-wrap:wrap;align-items:center;margin:.5rem 0}.v2 svg{max-width:100%;height:auto;border:1px solid #8886;border-radius:6px}
.v2 details{margin-left:1.1rem}.v2 summary{cursor:pointer}.v2 ul.tr2{list-style:none;padding-left:0}.v2 .leaf{margin-left:1.1rem}
.v2 .cols{display:grid;grid-template-columns:repeat(auto-fit,minmax(14rem,1fr));gap:.8rem}.v2 .col{border:1px solid #8886;border-radius:8px;padding:.5rem;background:#8881}
.v2 .col h2{font-size:.95rem;margin:.1rem 0 .4rem}.v2 .kcard{border:1px solid #8886;border-radius:6px;padding:.3rem .5rem;margin:.3rem 0;font-size:.9rem;background:#fff1}
.v2 .kcard .meta{font-size:.75rem;opacity:.7}.v2 .prio-high{border-left:4px solid #d9534f}.v2 .prio-medium{border-left:4px solid #e0a800}
.v2 table.mx{border-collapse:collapse;font-size:.7rem}.v2 table.mx td{width:1.4rem;height:1.4rem;padding:0;text-align:center;border:1px solid #8883}.v2 table.mx th{font-weight:normal;font-size:.7rem;max-width:7rem;overflow:hidden;white-space:nowrap;text-overflow:ellipsis;text-align:right}
.v2 table.mx th.cl{writing-mode:vertical-rl;text-align:left;max-height:7rem}.v2 .cell1{background:#4a90d966}.v2 .cell2{background:#4a90d9aa}.v2 .cell3{background:#4a90d9}
.v2 .lists{display:grid;grid-template-columns:repeat(auto-fit,minmax(16rem,1fr));gap:1rem}.v2 #stage{position:relative;height:36rem;border:1px solid #8886;border-radius:8px;overflow:hidden;touch-action:none}
.v2 .wcard{position:absolute;width:11rem;border:1px solid #8886;border-radius:6px;padding:.3rem .5rem;background:#ffd;color:#222;cursor:grab;user-select:none;font-size:.85rem}
.v2 .wcard.drag{cursor:grabbing;box-shadow:0 4px 12px #0006}.v2 #slide{border:1px solid #8886;border-radius:10px;padding:1.5rem 2rem;min-height:22rem;background:#fff1}.v2 #slide.full{position:fixed;inset:0;z-index:9;background:#fff;color:#111;overflow:auto;font-size:1.4rem}
.v2 .gal{display:grid;grid-template-columns:repeat(auto-fill,minmax(10rem,1fr));gap:.8rem}.v2 .gitem{border:1px solid #8886;border-radius:8px;padding:.4rem;font-size:.8rem;overflow:hidden}.v2 .gitem img{width:100%;height:7rem;object-fit:cover;border-radius:4px}
.v2 .gitem .ico{display:flex;align-items:center;justify-content:center;height:7rem;font-size:2rem;opacity:.7}.v2 .legend span{display:inline-block;margin-right:.8rem;font-size:.8rem}.v2 .legend i{display:inline-block;width:.8rem;height:.8rem;margin-right:.25rem;vertical-align:middle;border-radius:2px}
.v2 a.node text{cursor:pointer}.v2 .note{font-size:.85rem;opacity:.75}
"""


def split_slides(md: str) -> list[str]:
    """`---`（コードブロックの外の水平線）または `## ` 見出しで区切る。空のスライドは作らない。"""
    lines = md.replace("\r\n", "\n").split("\n")
    slides: list[str] = []
    cur: list[str] = []
    fence = False

    def flush():
        nonlocal cur
        t = "\n".join(cur).strip("\n")
        if t.strip():
            slides.append(t)
        cur = []

    for ln in lines:
        if re.match(r"^\s*(```|~~~)", ln):
            fence = not fence
        if not fence and re.match(r"^\s*(-{3,}|\*{3,}|_{3,})\s*$", ln):
            flush()
            continue
        if not fence and re.match(r"^##\s+", ln):
            flush()
        cur.append(ln)
    flush()
    return slides


_ATTR = re.compile(r'\b(src|href)="([^"]*)"')


def rebase_html(fragment: str, note_rel: str) -> str:
    """ノートの場所を基準にした相対パス（画像・リンク）を、サイトの最上位を基準にしたパスへ直す。
    スライドのページはサイトの最上位にあるので、サブフォルダのノートの `p.png` は `sub/p.png` にしないと壊れる。
    URL（`://` などの scheme）・`#…`・`/` で始まるもの・空は触らない。"""
    base = posixpath.dirname(note_rel)
    if not base:
        return fragment

    def fix(m):
        attr, val = m.group(1), m.group(2)
        if not val or val.startswith(("#", "/")) or re.match(r"^[A-Za-z][A-Za-z0-9+.-]*:", val):
            return m.group(0)
        mm = re.match(r"^([^#?]*)([#?].*)?$", val)
        path, rest = mm.group(1), mm.group(2) or ""
        joined = posixpath.normpath(posixpath.join(base, path)) if path else base
        return f'{attr}="{joined}{rest}"'

    return _ATTR.sub(fix, fragment)


def _fm_value(fm: list[str], key: str) -> str:
    for ln in fm:
        m = re.match(rf"^{key}:\s*(.*?)\s*$", ln)
        if m:
            return m.group(1).strip("'\"")
    return ""


def _is_true(fm: list[str], key: str) -> bool:
    return _fm_value(fm, key).lower() == "true"


def write(out: Path, root: Path, g, notes: dict, copied: set, assets: Path, page, out_name) -> list[str]:
    """追加ビューのデータとページを書く。書いたファイル名を返す。"""
    written: list[str] = []

    def w(name: str, text: str) -> None:
        (out / name).write_text(text, encoding="utf-8")
        written.append(name)

    for name in ("views2core.js", "views2.js"):
        shutil.copyfile(assets / name, out / name)
        written.append(name)
    css = (out / "style.css").read_text(encoding="utf-8")
    if "body.v2" not in css:
        (out / "style.css").write_text(css + "\n" + STYLE, encoding="utf-8")

    # --- タスク ---
    tasks = []
    for rel in notes:
        text = (root / rel).read_text(encoding="utf-8")
        for t in taskmod.parse_text(text, rel):
            tasks.append({"id": rel, "href": out_name(rel), "title": g.nodes[rel].title, "line": t.line, "text": t.text, "due": t.due, "scheduled": t.scheduled,
                          "start": t.start, "done": t.done, "done_date": t.done_date, "priority": t.priority})
    w("tasks-data.js", "window.GNOSIS_TASKS=" + json.dumps(tasks, ensure_ascii=False) + ";\n")

    # --- 添付 ---
    refs: dict[str, list[dict]] = {}
    for rel, d in notes.items():
        body = "\n".join(d["body"])
        for m in re.finditer(r"!?\[[^\]]*\]\(([^)\s]+)", body):
            url = m.group(1)
            if re.match(r"^[A-Za-z][A-Za-z0-9+.-]*:", url) or url.startswith(("#", "/")) or url.lower().split("#")[0].endswith(".md"):
                continue
            try:
                real = (root / rel).parent.joinpath(url.split("#", 1)[0]).resolve(strict=True)
            except OSError:
                continue
            if str(real) in copied:
                key = real.relative_to(root).as_posix()
                row = {"id": rel, "title": g.nodes[rel].title, "href": out_name(rel)}
                if row not in refs.setdefault(key, []):
                    refs[key].append(row)
    files = []
    for real in sorted(copied):
        rp = Path(real)
        key = rp.relative_to(root).as_posix()
        files.append({"name": key, "size": rp.stat().st_size, "notes": refs.get(key, [])})
    w("files-data.js", "window.GNOSIS_FILES=" + json.dumps(files, ensure_ascii=False) + ";\n")

    # --- スライド（front matter に slides: true を書いたノートだけ）---
    slides = []
    for rel, d in notes.items():
        if not _is_true(d["fm"], "slides"):
            continue
        pieces = split_slides("\n".join(l for l in d["body"] if l.strip() not in ("ParentBranch:", "Group:", "Context:", "Related:", "BackLink:")))
        slides.append({"id": rel, "title": g.nodes[rel].title, "href": out_name(rel), "slides": [rebase_html(md_html.render(p), rel) for p in pieces]})
    w("slides-data.js", "window.GNOSIS_SLIDES=" + json.dumps(slides, ensure_ascii=False) + ";\n")

    # --- ページ ---
    scripts = ('<script src="notes-data.js"></script><script src="graph-data.js"></script><script src="tasks-data.js"></script><script src="files-data.js"></script>'
               '<script src="slides-data.js"></script><script src="fznav-core.js"></script><script src="views2core.js"></script><script src="views2.js"></script>')
    for key, title, desc, view in VIEWS:
        nav = f'<p class="crumb"><a href="index.html">一覧</a> ・ <a href="views.html">ビュー一覧</a></p>'
        body = f'{nav}<h1>{html.escape(title)}</h1><p class="note">{html.escape(desc)}</p><div id="v2"></div><noscript>このビューには JavaScript が必要です。</noscript>{scripts}'
        w(f"{key}.html", page(title, body, body_class="v2", body_attrs=f'data-view2="{view}"'))
    items = "".join(f'<li><a href="{k}.html">{html.escape(t)}</a> — {html.escape(dsc)}</li>' for k, t, dsc, _ in VIEWS)
    w("views.html", page("ビュー一覧", f'<p class="crumb"><a href="index.html">一覧</a></p><h1>ビュー一覧</h1><ul>{items}</ul>'))
    return written
