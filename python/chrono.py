#!/usr/bin/env python3
"""時間軸の見方（TM02 カレンダー・TM10 日/週/月/年のレビュー・TM12 過去の今日）。読み取り専用。

日付の元は、ノートの front matter `time:`（作成日時）・ファイルの更新日時・タスクの 📅/✅。別の DB は持たない。
レビューを**ノートとして残す**のは `write-review` のときだけで、新しいノートを作る（既存は上書きしない）。

CLI（JSON。--md なら Markdown）:
  chrono.py ROOT calendar [YYYY-MM]              月のカレンダー（日ごとの新規ノート・期限・完了の件数）
  chrono.py ROOT day YYYY-MM-DD                  その日に作った・更新した・期限・完了したもの
  chrono.py ROOT onthisday [YYYY-MM-DD]          過去の同じ月日に作ったノート・終えたタスク
  chrono.py ROOT review 日|週|月|年 [YYYY-MM-DD]   期間の振り返り（件数・新しいノート・完了・未完了・次の期間の期限）
  chrono.py ROOT write-review 日|週|月|年 YYYY-MM-DD NEWFILE   レビューを新しいノートとして書く（既存は上書きしない）
"""
from __future__ import annotations

import calendar as _cal
import datetime as dt
import json
import os
import sys
from collections import defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import note_format_v2 as nf  # noqa: E402
import tasks as tk  # noqa: E402

PERIODS = {"日": "day", "週": "week", "月": "month", "年": "year", "day": "day", "week": "week", "month": "month", "year": "year"}
WEEKDAYS = "月火水木金土日"


def _notes(root: Path) -> list[dict]:
    out = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if not d.startswith(".")]
        for name in sorted(filenames):
            if not name.endswith(".md") or name.startswith("."):
                continue
            p = Path(dirpath) / name
            try:
                text = p.read_text(encoding="utf-8")
            except (OSError, UnicodeDecodeError):
                continue
            d = nf._simple_parse_text(p, text)
            tm = next((ln.split(":", 1)[1].strip() for ln in d["fm"] if ln.startswith("time:")), "")
            out.append({"path": p.relative_to(root).as_posix(), "title": d["title"], "created": tm[:10] if len(tm) >= 10 else "",
                        "modified": dt.date.fromtimestamp(p.stat().st_mtime).isoformat()})
    return out


def _range(period: str, on: dt.date) -> tuple[dt.date, dt.date]:
    period = PERIODS[period]
    if period == "day":
        return on, on
    if period == "week":
        a = on - dt.timedelta(days=on.weekday())
        return a, a + dt.timedelta(days=6)
    if period == "month":
        return on.replace(day=1), on.replace(day=_cal.monthrange(on.year, on.month)[1])
    return dt.date(on.year, 1, 1), dt.date(on.year, 12, 31)


def _in(day: str, a: dt.date, b: dt.date) -> bool:
    return bool(day) and a.isoformat() <= day <= b.isoformat()


def _ref(n: dict) -> dict:
    return {"path": n["path"], "title": n["title"]}


def _tref(t: tk.Task) -> dict:
    return {"file": t.file, "line": t.line, "text": t.text, "due": t.due, "done": t.done_date}


def calendar(root: str | Path, year: int, month: int) -> dict:
    root = Path(root).resolve()
    a, b = dt.date(year, month, 1), dt.date(year, month, _cal.monthrange(year, month)[1])
    days: dict[str, dict] = {}
    for d in range(1, b.day + 1):
        days[dt.date(year, month, d).isoformat()] = {"created": 0, "due": 0, "done": 0}
    for n in _notes(root):
        if _in(n["created"], a, b):
            days[n["created"]]["created"] += 1
    for t in tk.collect(root):
        if not t.done and _in(t.due, a, b):
            days[t.due]["due"] += 1
        if t.done and _in(t.done_date, a, b):
            days[t.done_date]["done"] += 1
    return {"year": year, "month": month, "days": days}


def calendar_md(c: dict) -> str:
    y, m = c["year"], c["month"]
    L = [f"# {y}年{m}月", "", "| " + " | ".join(WEEKDAYS) + " |", "|" + "---|" * 7]
    for week in _cal.Calendar(0).monthdayscalendar(y, m):
        cells = []
        for d in week:
            if not d:
                cells.append(" ")
                continue
            v = c["days"][dt.date(y, m, d).isoformat()]
            tag = "".join(x for x in (f"📝{v['created']}" if v["created"] else "", f"📅{v['due']}" if v["due"] else "", f"✅{v['done']}" if v["done"] else "") if x)
            cells.append(f"{d}" + (f"<br>{tag}" if tag else ""))
        L.append("| " + " | ".join(cells) + " |")
    L += ["", "📝 作ったノート　📅 期限のタスク　✅ 終えたタスク"]
    return "\n".join(L) + "\n"


def day(root: str | Path, on: dt.date) -> dict:
    root = Path(root).resolve()
    iso = on.isoformat()
    notes = _notes(root)
    ts = tk.collect(root)
    return {"date": iso, "created": [_ref(n) for n in notes if n["created"] == iso],
            "modified": [_ref(n) for n in notes if n["modified"] == iso and n["created"] != iso],
            "due": [_tref(t) for t in ts if not t.done and t.due == iso], "done": [_tref(t) for t in ts if t.done and t.done_date == iso]}


def on_this_day(root: str | Path, on: dt.date) -> dict:
    """過去の年の同じ月日に作ったノート・終えたタスク。今年の分は含めない。"""
    root = Path(root).resolve()
    md = on.strftime("%m-%d")
    years: dict[int, dict] = defaultdict(lambda: {"notes": [], "done": []})
    for n in _notes(root):
        if n["created"][5:] == md and n["created"][:4].isdigit() and int(n["created"][:4]) < on.year:
            years[int(n["created"][:4])]["notes"].append(_ref(n))
    for t in tk.collect(root):
        if t.done and t.done_date[5:] == md and t.done_date[:4].isdigit() and int(t.done_date[:4]) < on.year:
            years[int(t.done_date[:4])]["done"].append(_tref(t))
    return {"date": on.isoformat(), "years": [{"year": y, "years_ago": on.year - y, **v} for y, v in sorted(years.items(), reverse=True)]}


def review(root: str | Path, period: str, on: dt.date) -> dict:
    root = Path(root).resolve()
    if period not in PERIODS:
        raise ValueError("期間は 日・週・月・年 のどれかです")
    a, b = _range(period, on)
    nxt_a = b + dt.timedelta(days=1)
    _, nxt_b = _range(period, nxt_a)
    notes, ts = _notes(root), tk.collect(root)
    created = [n for n in notes if _in(n["created"], a, b)]
    return {"period": PERIODS[period], "from": a.isoformat(), "to": b.isoformat(),
            "created": [_ref(n) for n in created],
            "modified": [_ref(n) for n in notes if _in(n["modified"], a, b) and n not in created],
            "done": [_tref(t) for t in ts if t.done and _in(t.done_date, a, b)],
            "carried_over": [_tref(t) for t in ts if not t.done and t.due and t.due < a.isoformat()],
            "open_in_period": [_tref(t) for t in ts if not t.done and _in(t.due, a, b)],
            "next_due": [_tref(t) for t in ts if not t.done and _in(t.due, nxt_a, nxt_b)],
            "total_notes": len(notes)}


def _link(path: str, title: str) -> str:
    return f"[{title}]({path.replace(' ', '%20')})"


def review_md(r: dict) -> str:
    name = {"day": "日", "week": "週", "month": "月", "year": "年"}[r["period"]]
    L = [f"# {name}のレビュー {r['from']}" + ("" if r["from"] == r["to"] else f"〜{r['to']}"), "",
         f"- 作ったノート: {len(r['created'])} 件・更新したノート: {len(r['modified'])} 件・終えたタスク: {len(r['done'])} 件（全体 {r['total_notes']} ノート）", ""]
    def sect(title, items, fmt):
        L.extend([f"## {title}", ""] + ([fmt(x) for x in items[:50]] or ["- なし"]) + [""])
    sect("作ったノート", r["created"], lambda x: f"- {_link(x['path'], x['title'])}")
    sect("更新したノート", r["modified"], lambda x: f"- {_link(x['path'], x['title'])}")
    sect("終えたタスク", r["done"], lambda x: f"- {x['text']}（{x['done']}・{_link(x['file'], x['file'])}:{x['line']}）")
    sect("終わっていないタスク（期間中の期限・持ち越し）", r["open_in_period"] + r["carried_over"], lambda x: f"- {x['text']}（期限 {x['due']}・{_link(x['file'], x['file'])}:{x['line']}）")
    sect("次の期間の期限", r["next_due"], lambda x: f"- {x['text']}（{x['due']}）")
    L += ["## 振り返り（自分の言葉で）", "", "- うまくいったこと: ", "- 引っかかったこと: ", "- 次にやること: ", ""]
    return "\n".join(L)


def write_review(root: str | Path, period: str, on: dt.date, newfile: str, now: dt.datetime | None = None) -> dict:
    """レビューを新しいノートとして書く。既存のファイルは上書きしない。vault の外・ドット始まりのフォルダには書かない。"""
    root = Path(root).resolve()
    target = (root / newfile).resolve()
    try:
        rel = target.relative_to(root)
    except ValueError:
        raise ValueError("vault の外には書きません") from None
    if any(part.startswith(".") for part in rel.parts):
        raise ValueError("ドット始まりのフォルダには書きません")
    if target.exists():
        raise ValueError("すでにあります（上書きしません）: " + str(rel))
    r = review(root, period, on)
    now = now or dt.datetime.now()
    body = review_md(r)
    title = body.split("\n", 1)[0].lstrip("# ").strip()
    text = f"---\ntime: {now:%Y-%m-%d %H:%M:%S}\ntitle: {title}\n---\n\n{body}"
    target.parent.mkdir(parents=True, exist_ok=True)
    tmp = target.with_name(target.name + ".tmp")
    tmp.write_text(text, encoding="utf-8")
    os.replace(tmp, target)
    return {"path": rel.as_posix(), "title": title}


def day_md(d: dict) -> str:
    L = [f"# {d['date']}", ""]
    for title, items, fmt in (("作ったノート", d["created"], lambda x: f"- {_link(x['path'], x['title'])}"), ("更新したノート", d["modified"], lambda x: f"- {_link(x['path'], x['title'])}"),
                              ("期限のタスク", d["due"], lambda x: f"- {x['text']}（{_link(x['file'], x['file'])}:{x['line']}）"), ("終えたタスク", d["done"], lambda x: f"- {x['text']}（{_link(x['file'], x['file'])}:{x['line']}）")):
        L += [f"## {title}", ""] + ([fmt(x) for x in items] or ["- なし"]) + [""]
    return "\n".join(L)


def onthisday_md(o: dict) -> str:
    L = [f"# 過去の今日 {o['date'][5:]}", ""]
    for y in o["years"]:
        L += [f"## {y['year']} 年（{y['years_ago']} 年前）", ""] + [f"- {_link(x['path'], x['title'])}" for x in y["notes"]] + [f"- ✅ {x['text']}（{_link(x['file'], x['file'])}:{x['line']}）" for x in y["done"]] + [""]
    if not o["years"]:
        L.append("この日に過去に作ったノートはありません。")
    return "\n".join(L) + "\n"


def main(argv: list[str]) -> int:
    try:
        md = "--md" in argv
        a = [x for x in argv if x != "--md"]
        root, cmd, rest = a[0], a[1], a[2:]
        today = dt.date.today()
        if cmd == "calendar":
            y, m = (int(x) for x in rest[0].split("-")) if rest else (today.year, today.month)
            res = calendar(root, y, m)
            out = calendar_md(res)
        elif cmd == "day":
            res = day(root, dt.date.fromisoformat(rest[0]))
            out = day_md(res)
        elif cmd == "onthisday":
            res = on_this_day(root, dt.date.fromisoformat(rest[0]) if rest else today)
            out = onthisday_md(res)
        elif cmd == "review":
            res = review(root, rest[0], dt.date.fromisoformat(rest[1]) if len(rest) > 1 else today)
            out = review_md(res)
        elif cmd == "write-review":
            res = write_review(root, rest[0], dt.date.fromisoformat(rest[1]), rest[2])
            out = f"書きました: {res['path']}\n"
        else:
            print(__doc__, file=sys.stderr)
            return 2
        print(out, end="") if md else print(json.dumps(res, ensure_ascii=False))
    except (OSError, ValueError, IndexError, KeyError) as e:
        print(json.dumps({"error": str(e) or "引数が足りません"}, ensure_ascii=False))
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
