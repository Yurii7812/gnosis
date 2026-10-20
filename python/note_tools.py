#!/usr/bin/env python3
"""ノートの統計（ED17）と 2 ノートの比較（ED09）。読み取り専用。

stats: 本文（front matter と関係ブロックを除く）の文字数・語数・行数・見出し・リンク・タスク。vault 全体の合計と、大きいノート。
diff : 2 つのノートの本文を行ごとに比べる（unified diff）。近さ（0〜1）と、共通・片方だけの行数。ノートは変えない。

CLI（JSON。--md なら Markdown）:
  note_tools.py ROOT stats [NOTE]        1 つのノート、無ければ vault 全体
  note_tools.py ROOT diff A B [--context N]
  note_tools.py ROOT activity [--days N]  いつ書いたか・更新したか（作成日=front matter の time、更新日=ファイルの更新時刻）。月別・曜日別・直近の日別・連続日数
"""
from __future__ import annotations

import datetime as dt
import difflib
import json
import os
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import note_format_v2 as nf  # noqa: E402
import tasks as tk  # noqa: E402

LINK = re.compile(r"!?\[[^\]]*\]\([^)]*\)")
CJK = re.compile(r"[ぁ-んァ-ヶ一-龠ー]")
WORD = re.compile(r"[A-Za-z0-9][A-Za-z0-9_'’\-]*")
REL = {"ParentBranch:", "ChildBranch:", "BranchGroup:", "Group:", "Context:", "Related:", "BackLink:"}


def _resolve(root: Path, name: str) -> Path:
    p = (root / name)
    if p.is_file():
        return p.resolve()
    for q in sorted(root.rglob("*.md")):
        if q.name == name or q.stem == name or q.relative_to(root).as_posix() == name:
            return q
    raise ValueError("ノートが見つかりません: " + name)


def _body(path: Path) -> tuple[list[str], str]:
    text = path.read_text(encoding="utf-8")
    d = nf._simple_parse_text(path, text)
    return d["body"], d["title"]


def _prose(lines: list[str]) -> list[str]:
    """数える対象: 関係ブロック（見出し行とその直後のリンク行）を除く本文。"""
    out, skip = [], False
    for ln in lines:
        if ln.strip() in REL and ln == ln.lstrip():
            skip = True
            continue
        if skip:
            if not ln.strip():
                skip = False
            continue
        out.append(ln)
    return out


def _one(path: Path, root: Path) -> dict:
    body, title = _body(path)
    prose = _prose(body)
    text = "\n".join(prose)
    text_nocheck = re.sub(r"(?m)^(\s*[-*+]\s+)\[[ xX]\]\s?", r"\1", text)                 # タスクの [x] の印は語に数えない
    plain = LINK.sub(lambda m: re.sub(r"^!?\[|\]\(.*$", "", m.group(0)), text_nocheck)   # リンクは表示の文字だけ数える
    content = [x for x in prose if x.strip()]
    has_content = len(content) > (1 if content and re.match(r"^#\s", content[0]) else 0)   # 題（先頭の H1）だけなら中身は無い
    plain = re.sub(r"(?m)^\s*(#{1,6}\s+|[-*+]\s+|>\s*)", "", plain)                      # 見出しの #・箇条書きの印・引用の > は文字数に入れない
    chars = len(re.sub(r"\s", "", plain))
    tasks = tk.parse_text("\n".join(body), path.relative_to(root).as_posix())
    return {"path": path.relative_to(root).as_posix(), "title": title, "chars": chars, "cjk_chars": len(CJK.findall(plain)), "words": len(WORD.findall(plain)),
            "lines": len([x for x in prose if x.strip()]), "headings": len([x for x in prose if re.match(r"^#{1,6}\s", x)]),
            "links": len(LINK.findall(text)), "has_content": has_content, "tasks_open": sum(1 for t in tasks if not t.done), "tasks_done": sum(1 for t in tasks if t.done)}


def stats(root: str | Path, note: str | None = None, top: int = 10) -> dict:
    root = Path(root).resolve()
    if note:
        return {"note": _one(_resolve(root, note), root)}
    rows = [_one(p, root) for p in sorted(root.rglob("*.md")) if not any(x.startswith(".") for x in p.relative_to(root).parts)]
    tot = {k: sum(r[k] for r in rows) for k in ("chars", "cjk_chars", "words", "lines", "headings", "links", "tasks_open", "tasks_done")}
    return {"notes": len(rows), "total": tot, "average_chars": round(tot["chars"] / len(rows)) if rows else 0,
            "largest": sorted(({"path": r["path"], "title": r["title"], "chars": r["chars"]} for r in rows), key=lambda x: (-x["chars"], x["path"]))[:top],
            "empty": [r["path"] for r in rows if not r["has_content"]]}


def activity(root: str | Path, today: dt.date | None = None, days: int = 30, months: int = 12) -> dict:
    """編集の記録: 作成日（front matter の time）と更新日（ファイルの更新時刻）で、月別・曜日別・直近の日別の件数と、書いた日の連続日数。

    ファイルの更新時刻しか履歴が無いので、「その日に更新されたノートの数」であって、編集の回数や量ではない。"""
    root = Path(root).resolve()
    today = today or dt.date.today()
    days = max(1, min(int(days), 366))
    created: dict[str, int] = {}
    modified: dict[str, int] = {}
    chars_by_created: dict[str, int] = {}
    recent = []
    for p in sorted(root.rglob("*.md")):
        rel = p.relative_to(root)
        if any(x.startswith(".") for x in rel.parts):
            continue
        text = p.read_text(encoding="utf-8", errors="replace")
        m = re.search(r"(?m)^time:\s*(\d{4}-\d{2}-\d{2})", text[:600])
        mt = dt.date.fromtimestamp(p.stat().st_mtime)
        modified[mt.isoformat()] = modified.get(mt.isoformat(), 0) + 1
        if m:
            created[m.group(1)] = created.get(m.group(1), 0) + 1
            try:
                chars_by_created[m.group(1)] = chars_by_created.get(m.group(1), 0) + _one(p, root)["chars"]
            except (ValueError, OSError):
                pass
        recent.append((p.stat().st_mtime, rel.as_posix()))
    ym = lambda d: d[:7]
    cm: dict[str, int] = {}
    mm: dict[str, int] = {}
    for d, n in created.items():
        cm[ym(d)] = cm.get(ym(d), 0) + n
    for d, n in modified.items():
        mm[ym(d)] = mm.get(ym(d), 0) + n
    keys = []
    y, mo = today.year, today.month
    for _ in range(max(1, min(int(months), 120))):
        keys.append(f"{y:04d}-{mo:02d}")
        mo -= 1
        if mo == 0:
            y, mo = y - 1, 12
    keys.reverse()
    wd = [0] * 7
    for d, n in created.items():
        try:
            wd[dt.date.fromisoformat(d).weekday()] += n
        except ValueError:
            pass
    daily = []
    for i in range(days - 1, -1, -1):
        d = (today - dt.timedelta(days=i)).isoformat()
        daily.append({"date": d, "created": created.get(d, 0), "modified": modified.get(d, 0)})
    active = set(created) | set(modified)
    streak = 0
    d = today
    if d.isoformat() not in active:     # 今日まだ書いていなくても、昨日までの連続は切らない
        d -= dt.timedelta(days=1)
    while d.isoformat() in active:
        streak += 1
        d -= dt.timedelta(days=1)
    longest = run = 0
    prev = None
    for d in sorted(x for x in active if re.fullmatch(r"\d{4}-\d{2}-\d{2}", x)):
        cur = dt.date.fromisoformat(d)
        run = run + 1 if prev and (cur - prev).days == 1 else 1
        longest = max(longest, run)
        prev = cur
    return {"today": today.isoformat(), "months": [{"month": k, "created": cm.get(k, 0), "modified": mm.get(k, 0)} for k in keys],
            "weekday_created": wd, "daily": daily, "streak": streak, "longest_streak": longest,
            "recent": [r for _, r in sorted(recent, reverse=True)[:10]],
            "busiest_day": max(created.items(), key=lambda kv: (kv[1], kv[0]))[0] if created else None}


def diff(root: str | Path, a: str, b: str, context: int = 3) -> dict:
    root = Path(root).resolve()
    pa, pb = _resolve(root, a), _resolve(root, b)
    la, ta = _body(pa)
    lb, tb = _body(pb)
    ra, rb = pa.relative_to(root).as_posix(), pb.relative_to(root).as_posix()
    sm = difflib.SequenceMatcher(None, la, lb, autojunk=False)
    common = sum(m.size for m in sm.get_matching_blocks())
    ud = list(difflib.unified_diff(la, lb, ra, rb, lineterm="", n=max(0, context)))
    return {"a": ra, "b": rb, "similarity": round(sm.ratio(), 3), "common_lines": common, "only_a": len(la) - common, "only_b": len(lb) - common,
            "identical": la == lb, "diff": ud}


def to_md(kind: str, r: dict) -> str:
    if kind == "stats":
        if "note" in r:
            n = r["note"]
            return (f"# 統計: [{n['title']}]({n['path'].replace(' ', '%20')})\n\n- 文字数 {n['chars']}（うち日本語 {n['cjk_chars']}）・英数字の語 {n['words']}\n"
                    f"- 行 {n['lines']}・見出し {n['headings']}・リンク {n['links']}・タスク 未完了 {n['tasks_open']} / 完了 {n['tasks_done']}\n")
        t = r["total"]
        L = ["# vault の統計", "", f"- ノート {r['notes']} 件・文字数 {t['chars']}（平均 {r['average_chars']}）・語 {t['words']}・リンク {t['links']}", f"- タスク 未完了 {t['tasks_open']} / 完了 {t['tasks_done']}", "", "## 大きいノート", ""]
        L += [f"- [{x['title']}]({x['path'].replace(' ', '%20')}) — {x['chars']} 文字" for x in r["largest"]]
        if r["empty"]:
            L += ["", "## 本文が空のノート", ""] + [f"- [{p}]({p.replace(' ', '%20')})" for p in r["empty"][:30]]
        return "\n".join(L) + "\n"
    if kind == "activity":
        wn = "月火水木金土日"
        L = ["# 書いた・更新した記録", "", f"- 連続して書いた日 {r['streak']} 日（これまでの最長 {r['longest_streak']} 日）" + (f"・最も多く作った日 {r['busiest_day']}" if r["busiest_day"] else ""),
             "- 注: 「更新」はファイルの更新時刻で数えた、その日に変わったノートの数です（編集の回数・量ではありません）", "", "## 月ごと（作成 / 更新）", ""]
        L += [f"- {m['month']}: {m['created']} / {m['modified']}" for m in r["months"]]
        L += ["", "## 曜日ごとの作成", "", "- " + "　".join(f"{wn[i]} {n}" for i, n in enumerate(r["weekday_created"])), "", f"## 直近 {len(r['daily'])} 日（作成 / 更新）", ""]
        L += [f"- {d['date']}: {d['created']} / {d['modified']}" for d in r["daily"] if d["created"] or d["modified"]] or ["- なし"]
        L += ["", "## 最近更新したノート", ""] + [f"- [{x}]({x.replace(' ', '%20')})" for x in r["recent"]]
        return "\n".join(L) + "\n"
    L = [f"# 比較: {r['a']} と {r['b']}", "", ("同じ内容です。" if r["identical"] else f"近さ {r['similarity']}・共通 {r['common_lines']} 行・{r['a']} だけ {r['only_a']} 行・{r['b']} だけ {r['only_b']} 行"), ""]
    if r["diff"]:
        L += ["```diff"] + r["diff"] + ["```"]
    return "\n".join(L) + "\n"


def main(argv: list[str]) -> int:
    try:
        md = "--md" in argv
        ctx = 3
        a = []
        days = 30
        it = iter([x for x in argv if x != "--md"])
        for x in it:
            if x == "--context":
                ctx = int(next(it))
            elif x == "--days":
                days = int(next(it))
            else:
                a.append(x)
        root, cmd, rest = a[0], a[1], a[2:]
        if cmd == "stats":
            r = stats(root, rest[0] if rest else None)
        elif cmd == "activity":
            r = activity(root, days=days)
        elif cmd == "diff":
            r = diff(root, rest[0], rest[1], ctx)
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
