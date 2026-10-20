#!/usr/bin/env python3
"""Markdown 互換性検査（UT08）と性能診断（UT12）。読み取り専用。

compat: 他のアプリ（GitHub・Obsidian・一般の Markdown ビューア）で開いたときに崩れそうな書き方を、ノートごと・行ごとに挙げる。
  error … 構文が壊れている（閉じていないコードブロック・front matter、表の列数のずれ）
  warn  … 多くのアプリで意図どおり表示されない（空白を含む未エスケープのリンク先、CRLF 混在、BOM、リンク先の画像が無い）
  info  … Gnosis の拡張で、標準の Markdown では文字のまま見える（`==強調==`・`⏱`・`📖`・`⏰` などの印、`Group:` などの関係ブロック）。壊れてはいない
  fix できるもの（CRLF など）も、このツールは直さない。見つけるだけ。
profile: この環境での処理時間の目安（ノートの読み込み・関係グラフ・全文索引・類似度）と、大きい／遅いノート。

CLI（JSON。--md なら Markdown）:
  diagnose.py ROOT compat [--level error|warn|info]
  diagnose.py ROOT profile
"""
from __future__ import annotations

import json
import os
import re
import sys
import time
from collections import Counter
from pathlib import Path
from urllib.parse import unquote

sys.path.insert(0, str(Path(__file__).resolve().parent))
import tasks as tk  # noqa: E402

RANK = {"error": 0, "warn": 1, "info": 2}
LINK = re.compile(r"(!?)\[((?:\\.|[^\]\\])*)\]\(([^)]*)\)")
EXT_MARKS = [("==", re.compile(r"==(?!=).+?==")), ("⏱", re.compile(r"⏱")), ("🌱", re.compile(r"🌱")), ("📋", re.compile(r"📋")), ("📖", re.compile(r"📖")), ("⏰", re.compile(r"⏰")),
             ("❓", re.compile(r"❓")), ("🕰", re.compile(r"🕰")), ("📅", re.compile(r"📅"))]
REL_HEADS = {"ParentBranch:", "ChildBranch:", "BranchGroup:", "Group:", "Context:", "Related:", "BackLink:"}


def _row_cols(line: str) -> int:
    s = line.strip().strip("|")
    return len(re.split(r"(?<!\\)\|", s))


def check_note(root: Path, p: Path) -> list[dict]:
    rel = p.relative_to(root).as_posix()
    raw = p.read_bytes()
    out: list[dict] = []
    def add(level, line, code, msg):
        out.append({"file": rel, "line": line, "level": level, "code": code, "message": msg})
    if raw.startswith(b"\xef\xbb\xbf"):
        add("warn", 1, "bom", "ファイルの先頭に BOM があります（front matter が認識されないアプリがあります）")
    text = raw.decode("utf-8", errors="replace")
    if "\ufffd" in text:
        add("error", 1, "encoding", "UTF-8 として読めない文字があります")
    crlf = text.count("\r\n")
    lf_only = text.count("\n") - crlf
    if crlf and lf_only:
        add("warn", 1, "mixed-eol", f"改行コードが混在しています（CRLF {crlf} 行・LF {lf_only} 行）")
    lines = text.replace("\r\n", "\n").split("\n")
    start = 0
    if lines and lines[0].strip() == "---":
        end = next((i for i in range(1, len(lines)) if lines[i].strip() == "---"), None)
        if end is None:
            add("error", 1, "frontmatter-unclosed", "front matter（先頭の ---）が閉じていません")
        else:
            start = end + 1
    fence, fence_line, fence_mark = False, 0, ""
    heads: list[tuple[int, int, str]] = []
    table_cols: int | None = None
    ext_seen: Counter = Counter()
    ext_first: dict[str, int] = {}
    for i in range(start, len(lines)):
        ln = lines[i]
        no = i + 1
        st = ln.strip()
        m = re.match(r"^(```+|~~~+)", st)
        if m:
            if not fence:
                fence, fence_line, fence_mark = True, no, m.group(1)[0]
            elif st.startswith(fence_mark * 3):
                fence = False
            continue
        if fence:
            continue
        hm = re.match(r"^(#{1,6})\s+(.*?)\s*#*\s*$", ln)
        if hm:
            heads.append((no, len(hm.group(1)), hm.group(2)))
        if "|" in st and st.startswith("|"):
            cols = _row_cols(ln)
            if table_cols is None:
                table_cols = cols
            elif cols != table_cols and not re.fullmatch(r"\|?[\s:\-|]+\|?", st):
                add("error", no, "table-columns", f"表の列数が前の行と違います（{table_cols} 列 → {cols} 列）")
        else:
            table_cols = None
        for m in LINK.finditer(ln):
            tgt = m.group(3).strip()
            tgt_core = re.sub(r'\s+"[^"]*"$', "", tgt)
            if not tgt_core or tgt_core.startswith(("#", "mailto:")) or "://" in tgt_core:
                continue
            if " " in tgt_core and not tgt_core.startswith("<"):
                add("warn", no, "link-space", f"リンク先に空白があります（`%20` にするか `<…>` で囲む）: {tgt_core[:50]}")
                continue
            if m.group(1) == "!":
                path = unquote(tgt_core.split("#", 1)[0].split("?", 1)[0])
                if path and not (p.parent / path).resolve().exists():
                    add("warn", no, "image-missing", f"画像が見つかりません: {path}")
        if st in REL_HEADS and ln == ln.lstrip():
            ext_seen["関係ブロック"] += 1; ext_first.setdefault("関係ブロック", no)
        for name, rx in EXT_MARKS:
            if rx.search(ln):
                ext_seen[name] += 1; ext_first.setdefault(name, no)
    if fence:
        add("error", fence_line, "fence-unclosed", "コードブロックが閉じていません（以降が全部コード扱いになります）")
    seen: dict[str, int] = {}
    for no, lv, t in heads:
        key = t.lower()
        if key in seen:
            add("warn", no, "heading-duplicate", f"同じ見出し「{t}」が {seen[key]} 行目にもあります（#見出し のリンクが曖昧になります）")
        else:
            seen[key] = no
    prev = 0
    for no, lv, t in heads:
        if prev and lv > prev + 1:
            add("info", no, "heading-skip", f"見出しの階層が飛んでいます（H{prev} の次が H{lv}）")
        prev = lv
    for name, n in ext_seen.items():
        add("info", ext_first[name], "extension", f"Gnosis の拡張記法「{name}」が {n} 行あります（標準の Markdown では文字のまま表示されます）")
    return out


def compat(root: str | Path, level: str = "info") -> dict:
    if level not in RANK:
        raise ValueError("level は error / warn / info のどれかです")
    root = Path(root).resolve()
    items: list[dict] = []
    n = 0
    for p in tk.iter_notes(root):
        n += 1
        items += check_note(root, p)
    items = [x for x in items if RANK[x["level"]] <= RANK[level]]
    items.sort(key=lambda x: (RANK[x["level"]], x["file"], x["line"]))
    counts = Counter(x["level"] for x in items)
    return {"notes": n, "counts": {k: counts.get(k, 0) for k in RANK}, "items": items,
            "note_text": "見つけるだけで、ノートは直しません。info は壊れているのではなく、Gnosis の拡張です。"}


def _timed(fn):
    t = time.perf_counter()
    r = fn()
    return r, round(time.perf_counter() - t, 3)


def profile(root: str | Path) -> dict:
    root = Path(root).resolve()
    import gnosis_graph as gg
    import local_ai as ai
    import vault_index as vi
    notes = list(tk.iter_notes(root))
    sizes = sorted(((p.stat().st_size, p.relative_to(root).as_posix()) for p in notes), reverse=True)
    def read_all():
        slow = []
        for p in notes:
            t = time.perf_counter()
            p.read_text(encoding="utf-8")
            slow.append((time.perf_counter() - t, p.relative_to(root).as_posix()))
        return slow
    slow, t_read = _timed(read_all)
    g, t_graph = _timed(lambda: gg.build(root))
    # 全文索引は、実 vault の .gnosis に書かないよう、ノートへのシンボリックリンクだけを置いた一時フォルダで作って測る
    import tempfile
    with tempfile.TemporaryDirectory() as td:
        farm = Path(td)
        for p in notes:
            link = farm / p.relative_to(root)
            link.parent.mkdir(parents=True, exist_ok=True)
            link.symlink_to(p)
        _, t_index = _timed(lambda: vi.search(farm, "あ", limit=1))
    c, t_corpus = _timed(lambda: ai.Corpus.build(root))
    total = sum(s for s, _ in sizes)
    return {"notes": len(notes), "bytes": total, "avg_bytes": round(total / len(notes)) if notes else 0,
            "largest": [{"file": f, "bytes": s} for s, f in sizes[:5]],
            "seconds": {"read_all": t_read, "graph": t_graph, "full_text_index": t_index, "similarity_corpus": t_corpus},
            "nodes": len(g.nodes), "edges": len(g.edges),
            "note_text": "この環境での実測値です（初回のみの処理も含む）。派生データ（索引など）は消しても作り直せます。"}


def to_md(kind: str, r: dict) -> str:
    L: list[str] = []
    if kind == "compat":
        c = r["counts"]
        L = ["# Markdown 互換性検査", "", f"ノート {r['notes']} 件・error {c['error']}・warn {c['warn']}・info {c['info']}", ""]
        cur = None
        for x in r["items"]:
            if x["level"] != cur:
                cur = x["level"]; L += [f"## {cur}", ""]
            L.append(f"- [{x['file']}]({x['file'].replace(' ', '%20')}):{x['line']} {x['message']}")
        if not r["items"]:
            L.append("問題は見つかりませんでした。")
        L += ["", r["note_text"]]
    else:
        s = r["seconds"]
        L = ["# 性能診断", "", f"- ノート {r['notes']} 件・{r['bytes']:,} バイト（平均 {r['avg_bytes']:,}）・関係 {r['nodes']} ノード / {r['edges']} 辺", "",
             "## 処理時間（秒）", "", f"- 全ノートの読み込み {s['read_all']}", f"- 関係グラフ {s['graph']}", f"- 全文索引 {s['full_text_index'] if s['full_text_index'] is not None else '（計測せず）'}", f"- 類似度の準備 {s['similarity_corpus']}", "",
             "## 大きいノート", ""] + [f"- [{x['file']}]({x['file'].replace(' ', '%20')}) — {x['bytes']:,} バイト" for x in r["largest"]] + ["", r["note_text"]]
    return "\n".join(L) + "\n"


def main(argv: list[str]) -> int:
    try:
        md = "--md" in argv
        level = "info"
        a = []
        it = iter([x for x in argv if x != "--md"])
        for x in it:
            if x == "--level":
                level = next(it)
            else:
                a.append(x)
        root, cmd = a[0], a[1]
        if cmd == "compat":
            r = compat(root, level)
        elif cmd == "profile":
            r = profile(root)
        else:
            print(__doc__, file=sys.stderr)
            return 2
        print(to_md(cmd, r), end="") if md else print(json.dumps(r, ensure_ascii=False))
    except (OSError, ValueError, IndexError, StopIteration) as e:
        print(json.dumps({"error": str(e) or "引数が足りません"}, ensure_ascii=False))
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
