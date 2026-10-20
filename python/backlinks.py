#!/usr/bin/env python3
"""バックリンクと未リンクの言及（ED01・ED02）。読み取り専用。

backlinks(note) … このノートを指している他のノートを、関係の種類（本文のリンク・Context・Related・ParentBranch・Group …）と、
                  リンクのある行の前後（プレビュー）つきで返す。種類を潰さず、出典ノートの題と番号も付ける。
unlinked(note)  … このノートの題が、他のノートの本文に**文字として**出ているが、リンクされていないもの（文字列の一致）。
                  意味の近さによる候補は local_ai の links が出す。ここでは文字の一致だけを扱う（二つを混ぜない）。
CLI（JSON。--md なら Markdown）:  backlinks.py ROOT NOTE [--unlinked] [--md]
"""
from __future__ import annotations

import json
import os
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import gnosis_graph as gg  # noqa: E402
import note_format_v2 as nf  # noqa: E402

KIND_LABEL = {"link": "本文のリンク", "context": "Context", "related": "Related", "parent_branch": "ParentBranch（子から親）", "group": "Group（所属）",
              "branch_group": "BranchGroup（親から子）", "child_branch": "ChildBranch", "backlink": "BackLink 欄", "folgezettel": "Folgezettel の親子"}


def _resolve(g: gg.Graph, note: str) -> str:
    if note in g.nodes:
        return note
    for r, n in g.nodes.items():
        if r.endswith("/" + note) or n.title == note or Path(r).stem == note:
            return r
    raise ValueError("ノートが見つかりません: " + note)


def _context(root: Path, src: str, target_name: str, radius: int = 1) -> dict:
    """src の中で target_name へのリンクがある最初の行と、その前後。"""
    try:
        lines = (root / src).read_text(encoding="utf-8").split("\n")
    except OSError:
        return {"line": 0, "text": "", "before": [], "after": []}
    for i, ln in enumerate(lines):
        if re.search(r"\]\([^)]*" + re.escape(target_name) + r"(?:[#)\s])", ln):
            return {"line": i + 1, "text": ln.strip(), "before": [x.strip() for x in lines[max(0, i - radius):i] if x.strip()], "after": [x.strip() for x in lines[i + 1:i + 1 + radius] if x.strip()]}
    return {"line": 0, "text": "", "before": [], "after": []}


def backlinks(root: str | Path, note: str) -> dict:
    root = Path(root).resolve()
    g = gg.build(root)
    rel = _resolve(g, note)
    name = Path(rel).name
    by_src: dict[str, set[str]] = {}
    for e in g.edges:
        if e.dst == rel and e.src != rel:
            by_src.setdefault(e.src, set()).add(e.kind)
    rows = []
    for src, kinds in by_src.items():
        n = g.nodes[src]
        real = sorted(k for k in kinds if k not in ("backlink", "folgezettel"))
        derived = sorted(k for k in kinds if k in ("backlink", "folgezettel"))
        rows.append({"path": src, "title": n.title, "fz": n.fz, "kinds": real, "kind_labels": [KIND_LABEL.get(k, k) for k in real],
                     "derived": derived, "preview": _context(root, src, name)})
    rows.sort(key=lambda r: (bool(not r["kinds"]), r["fz"] == "", r["title"]))
    return {"note": rel, "title": g.nodes[rel].title, "count": len(rows), "backlinks": rows}


def unlinked(root: str | Path, note: str, min_len: int = 3, limit: int = 50) -> dict:
    """他のノートの本文に題が文字として出ているが、リンクされていないもの。コードブロック・リンクの中の一致は数えない。"""
    root = Path(root).resolve()
    g = gg.build(root)
    rel = _resolve(g, note)
    title = g.nodes[rel].title.strip()
    out = []
    if len(title) >= min_len:
        linked_from = {e.src for e in g.edges if e.dst == rel}
        for src, n in sorted(g.nodes.items()):
            if src == rel or src in linked_from:
                continue
            try:
                lines = (root / src).read_text(encoding="utf-8").split("\n")
            except OSError:
                continue
            fence = False
            for i, ln in enumerate(lines):
                if ln.strip().startswith(("```", "~~~")):
                    fence = not fence
                    continue
                if fence:
                    continue
                plain = re.sub(r"!?\[[^\]]*\]\([^)]*\)", " ", ln)          # リンクの中の文字は除く
                plain = re.sub(r"`[^`]*`", " ", plain)
                if title.lower() in plain.lower():
                    out.append({"path": src, "title": n.title, "line": i + 1, "text": ln.strip()[:160]})
                    break
            if len(out) >= limit:
                break
    return {"note": rel, "title": title, "count": len(out), "unlinked": out}


def to_md(bl: dict, ul: dict | None = None) -> str:
    L = [f"# バックリンク: {bl['title']}", "", f"{bl['count']} 件のノートがこのノートを指しています。", ""]
    for r in bl["backlinks"]:
        label = " / ".join(r["kind_labels"]) or "（BackLink 欄・番号の親子のみ）"
        L.append(f"- [{(r['fz'] + ' ') if r['fz'] else ''}{r['title']}]({r['path'].replace(' ', '%20')}) — {label}")
        p = r["preview"]
        if p["text"]:
            L.append(f"  - {p['line']} 行: {p['text']}")
    if ul is not None:
        L += ["", f"# 未リンクの言及（文字の一致）: {ul['count']} 件", ""]
        L += [f"- [{x['title']}]({x['path'].replace(' ', '%20')}) — {x['line']} 行: {x['text']}" for x in ul["unlinked"]] or ["- なし"]
    return "\n".join(L) + "\n"


def main(argv: list[str]) -> int:
    try:
        md = "--md" in argv
        un = "--unlinked" in argv
        a = [x for x in argv if not x.startswith("--")]
        if len(a) != 2:
            print(__doc__, file=sys.stderr)
            return 2
        bl = backlinks(a[0], a[1])
        ul = unlinked(a[0], a[1]) if un or md else None
        print(to_md(bl, ul), end="") if md else print(json.dumps({**bl, **({"unlinked": ul["unlinked"]} if ul else {})}, ensure_ascii=False))
    except (OSError, ValueError) as e:
        print(json.dumps({"error": str(e)}, ensure_ascii=False))
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
