#!/usr/bin/env python3
"""PARA の仮想ビュー（KM01）と MOC・索引案（KM03）。

PARA: ノートを Projects / Areas / Resources / Archives に**分けて見せるだけ**。ノートの移動も、`para:` の書き込みもしない。
  分類の根拠は必ず出す。利用者が front matter に `para: project|area|resource|archive` と書いていれば、それが最優先。
  無ければ状態から導く（Project: 未完了のタスクがある。Archive: 長く触っておらず未完了のタスクもない。Area: グループ（索引）。Resource: それ以外）。
MOC: グループ（索引）の中身を、小グループごとにまとめて表示する。**既存の索引は書き換えない**。
  索引案は、語や複数のノートから「新しいノートの草稿」を作る。書くのは `--write NEWFILE`（新規のみ・既存は上書きしない）のときだけ。
  草稿はふつうのノート（`moc: true`）で、`attribute: group` は付けない（グループ化は Gnosis の通常の手順で行う）。

CLI（JSON。--md なら Markdown）:
  para_moc.py ROOT para [--days N]                   4 つに分けて一覧（根拠つき）
  para_moc.py ROOT moc GROUP                         グループの中身（小グループごと）
  para_moc.py ROOT propose '語' [--k N] [--write NEWFILE]   語に近いノートから索引案
"""
from __future__ import annotations

import datetime as dt
import json
import os
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import gnosis_graph as gg  # noqa: E402
import local_ai as ai  # noqa: E402
import tasks as tk  # noqa: E402

CATS = {"project": "Projects（期限のある取り組み）", "area": "Areas（続けて見ている領域）", "resource": "Resources（参考・資料）", "archive": "Archives（終わった・古い）"}
EXPLICIT = re.compile(r"^para:\s*(project|area|resource|archive)s?\s*$", re.I | re.M)


def para(root: str | Path, days: int = 365, today: dt.date | None = None) -> dict:
    root = Path(root).resolve()
    today = today or dt.date.today()
    g = gg.build(root)
    open_tasks: dict[str, int] = {}
    for t in tk.collect(root):
        if not t.done:
            open_tasks[t.file] = open_tasks.get(t.file, 0) + 1
    out: dict[str, list] = {k: [] for k in CATS}
    for rel, n in sorted(g.nodes.items()):
        try:
            text = (root / rel).read_text(encoding="utf-8")
        except OSError:
            continue
        head = text.split("\n---", 1)[0] if text.startswith("---") else ""          # front matter だけ
        age = (today - dt.date.fromtimestamp((root / rel).stat().st_mtime)).days
        m = EXPLICIT.search(head)
        if m:
            cat, why = m.group(1).lower(), f"front matter の para: {m.group(1).lower()}（自分で指定）"
        elif open_tasks.get(rel):
            cat, why = "project", f"未完了のタスクが {open_tasks[rel]} 件ある"
        elif age >= days:
            cat, why = "archive", f"{age} 日触っておらず、未完了のタスクもない"
        elif n.is_group:
            cat, why = "area", "グループ（索引）"
        else:
            cat, why = "resource", "上のどれにも当たらない（参考・資料として扱う）"
        out[cat].append({"path": rel, "title": n.title, "why": why, "explicit": bool(m)})
    return {"days": days, "counts": {k: len(v) for k, v in out.items()}, "categories": out,
            "note_text": "見せ方だけです。ノートは移動も変更もしていません。違うと思うときは front matter に para: を書くと、そちらが優先されます。"}


def members(g: gg.Graph, group: str) -> list[str]:
    """グループに属する（Group: でこのグループを指す）ノート、およびこのグループが BranchGroup:・本文リンクで挙げているノート。"""
    out = []
    for e in g.edges:
        if e.derived and e.kind != "group":
            continue
        if e.kind == "group" and e.dst == group and e.src != group:
            out.append(e.src)
        elif e.kind in ("branch_group", "link", "child_branch") and e.src == group and e.dst != group:
            out.append(e.dst)
    return sorted(set(out), key=lambda r: (g.nodes[r].fz == "", g.nodes[r].fz, g.nodes[r].title))


def _find(g: gg.Graph, name: str) -> str:
    if name in g.nodes:
        return name
    for r, n in sorted(g.nodes.items()):
        if r.endswith("/" + name) or n.title == name or Path(r).stem == name:
            return r
    raise ValueError("ノートが見つかりません: " + name)


def moc(root: str | Path, group: str) -> dict:
    g = gg.build(root)
    gid = _find(g, group)
    sub, plain = [], []
    for m in members(g, gid):
        n = g.nodes[m]
        if n.is_group:
            sub.append({"path": m, "title": n.title, "members": [{"path": c, "title": g.nodes[c].title, "fz": g.nodes[c].fz} for c in members(g, m) if c != gid]})
        else:
            plain.append({"path": m, "title": n.title, "fz": n.fz})
    return {"group": gid, "title": g.nodes[gid].title, "is_group": g.nodes[gid].is_group, "subgroups": sub, "notes": plain,
            "count": len(plain) + sum(len(s["members"]) for s in sub)}


def propose(root: str | Path, query: str, k: int = 12) -> dict:
    """語に近いノートを集め、すでに同じ索引に載っているものは「載っている」と示した、索引の草稿を作る（まだ何も書かない）。"""
    root = Path(root).resolve()
    c = ai.Corpus.build(root)
    g = gg.build(root)
    hits = ai.semantic(c, query, k)
    if not hits:
        return {"query": query, "items": [], "draft": "", "note_text": "近いノートが見つかりませんでした。"}
    in_groups: dict[str, list[str]] = {}
    for gid, n in g.nodes.items():
        if n.is_group:
            for m in members(g, gid):
                in_groups.setdefault(m, []).append(n.title)
    items = [{"path": h["path"], "title": h["title"], "score": h["score"], "already_in": sorted(in_groups.get(h["path"], []))} for h in hits]
    L = [f"# {query}の索引（案）", "", "語に近いノートを集めた草稿です。内容を見て、載せるものを選んでください。", ""]
    for it in items:
        mark = f"（すでに「{'・'.join(it['already_in'])}」に載っている）" if it["already_in"] else ""
        L.append(f"- [{it['title']}]({it['path'].replace(' ', '%20')}){mark}")
    return {"query": query, "items": items, "draft": "\n".join(L) + "\n",
            "note_text": "草稿です。既存の索引は変えません。保存するときは新しいノートとしてだけ書きます。"}


def write_draft(root: str | Path, query: str, newfile: str, k: int = 12, now: dt.datetime | None = None) -> dict:
    root = Path(root).resolve()
    target = (root / newfile).resolve()
    try:
        rel = target.relative_to(root)
    except ValueError:
        raise ValueError("vault の外には書きません") from None
    if any(p.startswith(".") for p in rel.parts):
        raise ValueError("ドット始まりのフォルダには書きません")
    if target.exists():
        raise ValueError("すでにあります（上書きしません）: " + str(rel))
    p = propose(root, query, k)
    if not p["items"]:
        raise ValueError("近いノートが見つからないので書きません")
    now = now or dt.datetime.now()
    title = f"{query}の索引（案）"
    body = p["draft"].split("\n", 2)[2]
    text = f"---\ntime: {now:%Y-%m-%d %H:%M:%S}\ntitle: {title}\nmoc: true\n---\n\n# {title}\n{body}"
    target.parent.mkdir(parents=True, exist_ok=True)
    tmp = target.with_name(target.name + ".tmp")
    tmp.write_text(text, encoding="utf-8")
    os.replace(tmp, target)
    return {"path": rel.as_posix(), "title": title, "items": len(p["items"])}


def _l(p, t):
    return f"[{t}]({p.replace(' ', '%20')})"


def to_md(kind: str, r: dict) -> str:
    L: list[str] = []
    if kind == "para":
        L = ["# PARA（仮想ビュー）", "", r["note_text"], ""]
        for k, title in CATS.items():
            L += [f"## {title} — {r['counts'][k]} 件", ""] + [f"- {_l(x['path'], x['title'])} — {x['why']}" for x in r["categories"][k][:100]] + [""]
    elif kind == "moc":
        L = [f"# MOC: {r['title']}", "", f"{r['count']} 件" + ("" if r["is_group"] else "（このノートはグループではありません。リンクしているノートを並べています）"), ""]
        for s in r["subgroups"]:
            L += [f"## {_l(s['path'], s['title'])}", ""] + [f"- {_l(m['path'], m['title'])}" for m in s["members"]] + [""]
        L += ["## 直接のノート", ""] + [f"- {(x['fz'] + ' ') if x['fz'] else ''}{_l(x['path'], x['title'])}" for x in r["notes"]] + [""]
    elif kind == "propose":
        L = [r["draft"] or "近いノートが見つかりませんでした。\n", r["note_text"]]
    return "\n".join(L) + "\n"


def main(argv: list[str]) -> int:
    try:
        md = "--md" in argv
        opts, rest, it = {}, [], iter([x for x in argv if x != "--md"])
        for x in it:
            if x in ("--days", "--k"):
                opts[x[2:]] = int(next(it))
            elif x == "--write":
                opts["write"] = next(it)
            else:
                rest.append(x)
        root, cmd, a = rest[0], rest[1], rest[2:]
        if cmd == "para":
            r = para(root, opts.get("days", 365))
        elif cmd == "moc":
            r = moc(root, a[0])
        elif cmd == "propose":
            r = write_draft(root, a[0], opts["write"], opts.get("k", 12)) if "write" in opts else propose(root, a[0], opts.get("k", 12))
            if "write" in opts:
                print(json.dumps(r, ensure_ascii=False))
                return 0
        else:
            print(__doc__, file=sys.stderr)
            return 2
        print(to_md(cmd, r), end="") if md else print(json.dumps(r, ensure_ascii=False))
    except (OSError, ValueError, IndexError) as e:
        print(json.dumps({"error": str(e) or "引数が足りません"}, ensure_ascii=False))
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
