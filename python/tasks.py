#!/usr/bin/env python3
"""Markdown のタスク（`- [ ]`）を読む・集める・完了する共通エンジン。

PC の Agenda、`\\A` のカレンダー、Android の通知が同じ解析を使えるようにする（仕様 TM01〜TM09・AN02）。
ノート本文のタスク行をそのまま原本とし、別の DB を持たない（集めた結果は派生データ）。

行の書き方（ふつうの Markdown のまま。印は行のどこにあってもよい）:
  - [ ] 本文 📅 2026-10-25            … 期限（`due:2026-10-25` でも可。時刻は `📅 2026-10-25 09:30`）
  - [ ] 本文 ⏳ 2026-10-23            … 予定日（`scheduled:`）
  - [ ] 本文 🛫 2026-10-20            … 開始日（`start:`）。その日までは Agenda に出さない
  - [ ] 本文 🔁 weekly               … 繰り返し（`repeat:`）。daily / weekly / monthly / yearly / weekday / every N days|weeks|months|years
  - [ ] 本文 ⏫ / 🔼 / 🔽            … 優先度（高・中・低）
  - [ ] 本文 id:a1  /  after:a1      … 依存関係（after の相手が未完了ならブロック中）
  - [x] 本文 ✅ 2026-10-20           … 完了日（`done:`）
コードブロックの中の `- [ ]` はタスクではない。

CLI（JSON）:
  tasks.py agenda ROOT [YYYY-MM-DD]       期限切れ・今日・近日・期限なしに分けて出す
  tasks.py complete FILE LINE [YYYY-MM-DD]  完了にする（繰り返しは次の回を作る）。LINE は 1 から
"""
from __future__ import annotations

import calendar
import datetime as dt
import json
import os
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

TASK_RE = re.compile(r"^(?P<indent>\s*)(?P<bullet>[-*+]) \[(?P<mark>[ xX])\] ?(?P<text>.*)$")
_DATE = r"(\d{4}-\d{2}-\d{2})(?:[ T](\d{1,2}:\d{2}))?"
DUE_RE = re.compile(r"(?:📅|\bdue:)\s*" + _DATE)
SCHED_RE = re.compile(r"(?:⏳|\bscheduled:)\s*" + _DATE)
START_RE = re.compile(r"(?:🛫|\bstart:)\s*" + _DATE)
DONE_RE = re.compile(r"(?:✅|\bdone:)\s*" + _DATE)
REPEAT_RE = re.compile(r"(?:🔁|\brepeat:)\s*([A-Za-z]+(?: \d+ [a-z]+)?|every \d+ [a-z]+)")
ID_RE = re.compile(r"(?<![\w-])id:([\w-]+)")
AFTER_RE = re.compile(r"(?<![\w-])after:([\w-]+)")
PRIORITY = {"⏫": "high", "🔼": "medium", "🔽": "low"}


@dataclass
class Task:
    file: str
    line: int                 # 1 から
    done: bool
    text: str                 # 印を除いた本文
    raw: str
    due: str = ""             # YYYY-MM-DD
    due_time: str = ""        # HH:MM
    scheduled: str = ""
    start: str = ""
    done_date: str = ""
    repeat: str = ""
    priority: str = ""
    tid: str = ""
    after: list[str] = field(default_factory=list)
    blocked: bool = False


def _strip_marks(text: str) -> str:
    for rx in (DUE_RE, SCHED_RE, START_RE, DONE_RE, REPEAT_RE, ID_RE, AFTER_RE):
        text = rx.sub("", text)
    for m in PRIORITY:
        text = text.replace(m, "")
    return re.sub(r"\s{2,}", " ", text).strip()


def parse_line(raw: str, file: str = "", line: int = 0) -> Task | None:
    m = TASK_RE.match(raw)
    if not m:
        return None
    body = m.group("text")
    t = Task(file=file, line=line, done=m.group("mark") in "xX", text=_strip_marks(body), raw=raw)
    if (x := DUE_RE.search(body)):
        t.due, t.due_time = x.group(1), x.group(2) or ""
    if (x := SCHED_RE.search(body)):
        t.scheduled = x.group(1)
    if (x := START_RE.search(body)):
        t.start = x.group(1)
    if (x := DONE_RE.search(body)):
        t.done_date = x.group(1)
    if (x := REPEAT_RE.search(body)):
        t.repeat = x.group(1).strip().lower()
    t.priority = next((v for k, v in PRIORITY.items() if k in body), "")
    if (x := ID_RE.search(body)):
        t.tid = x.group(1)
    t.after = AFTER_RE.findall(body)
    return t


def parse_text(text: str, file: str = "") -> list[Task]:
    out = []
    fence = ""
    for n, ln in enumerate(text.split("\n"), 1):
        s = ln.lstrip()
        if s.startswith(("```", "~~~")):
            mark = s[:3]
            fence = "" if fence == mark else (fence or mark)
            continue
        if fence:
            continue
        t = parse_line(ln, file, n)
        if t:
            out.append(t)
    return out


def add_interval(day: dt.date, n: int, unit: str) -> dt.date:
    if unit.startswith("day"):
        return day + dt.timedelta(days=n)
    if unit.startswith("week"):
        return day + dt.timedelta(weeks=n)
    if unit.startswith(("month", "year")):
        months = n * (12 if unit.startswith("year") else 1)
        y, m = divmod(day.year * 12 + day.month - 1 + months, 12)
        m += 1
        return dt.date(y, m, min(day.day, calendar.monthrange(y, m)[1]))  # 31 日 → 翌月末に丸める
    raise ValueError("繰り返しの単位が分かりません: " + unit)


def next_occurrence(day: dt.date, rule: str) -> dt.date:
    rule = rule.strip().lower()
    simple = {"daily": (1, "day"), "weekly": (1, "week"), "monthly": (1, "month"), "yearly": (1, "year")}
    if rule in simple:
        return add_interval(day, *simple[rule])
    if rule in ("weekday", "weekdays"):
        nxt = day + dt.timedelta(days=1)
        while nxt.weekday() >= 5:
            nxt += dt.timedelta(days=1)
        return nxt
    m = re.fullmatch(r"every (\d+) ([a-z]+)", rule)
    if m:
        return add_interval(day, int(m.group(1)), m.group(2))
    raise ValueError("繰り返しの規則が分かりません: " + rule)


def iter_notes(root: Path):
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if not d.startswith(".")]
        for name in sorted(filenames):
            if name.endswith(".md") and not name.startswith("."):
                yield Path(dirpath) / name


def collect(root: str | Path) -> list[Task]:
    root = Path(root)
    tasks: list[Task] = []
    for p in iter_notes(root):
        try:
            text = p.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        tasks += parse_text(text, p.relative_to(root).as_posix())
    open_ids = {t.tid for t in tasks if t.tid and not t.done}
    for t in tasks:
        t.blocked = (not t.done) and any(a in open_ids for a in t.after)
    return tasks


def agenda(tasks: list[Task], today: dt.date, soon_days: int = 7) -> dict:
    """未完了のタスクを期限切れ・今日・近日・期限なしに分ける。開始日前のものと、ブロック中は別に数える。"""
    iso = today.isoformat()
    soon = (today + dt.timedelta(days=soon_days)).isoformat()
    out: dict[str, list] = {"overdue": [], "today": [], "soon": [], "later": [], "undated": [], "blocked": [], "not_started": []}
    for t in tasks:
        if t.done:
            continue
        if t.start and t.start > iso:
            out["not_started"].append(t)
        elif t.blocked:
            out["blocked"].append(t)
        else:
            day = t.due or t.scheduled
            if not day:
                out["undated"].append(t)
            elif day < iso:
                out["overdue"].append(t)
            elif day == iso:
                out["today"].append(t)
            elif day <= soon:
                out["soon"].append(t)
            else:
                out["later"].append(t)
    rank = {"high": 0, "medium": 1, "low": 2, "": 3}
    for k in out:
        out[k].sort(key=lambda t: (t.due or t.scheduled or "9999", t.due_time or "99:99", rank[t.priority], t.file, t.line))
    return out


def _atomic_write(path: Path, text: str) -> None:
    tmp = path.with_name(path.name + ".gnosis-tmp")
    tmp.write_text(text, encoding="utf-8")
    os.replace(tmp, path)


def complete(path: str | Path, line: int, today: dt.date) -> dict:
    """行 line（1 から）のタスクを完了にする。繰り返しは、完了した行の下に次の回（未完了）を作る。
    行がタスクでない・すでに完了のときは何も書かない。"""
    path = Path(path)
    text = path.read_text(encoding="utf-8")
    lines = text.split("\n")
    if not 1 <= line <= len(lines):
        raise ValueError("行がありません")
    t = parse_line(lines[line - 1], str(path), line)
    if t is None:
        return {"ok": False, "error": "タスクの行ではありません"}
    if t.done:
        return {"ok": True, "changed": False}
    done_line = TASK_RE.sub(lambda m: f"{m.group('indent')}{m.group('bullet')} [x] {m.group('text')}", lines[line - 1], count=1)
    if not t.done_date:
        done_line = done_line.rstrip() + f" ✅ {today.isoformat()}"
    new_lines = [done_line]
    if t.repeat:
        base = dt.date.fromisoformat(t.due or t.scheduled or today.isoformat())
        nxt = next_occurrence(base, t.repeat)
        nxt_line = lines[line - 1]
        for rx, key in ((DUE_RE, "due"), (SCHED_RE, "sched"), (START_RE, "start")):
            def bump(m, key=key):
                d = next_occurrence(dt.date.fromisoformat(m.group(1)), t.repeat)
                return m.group(0).replace(m.group(1), d.isoformat())
            nxt_line = rx.sub(bump, nxt_line)
        if not t.due and not t.scheduled:
            nxt_line = nxt_line.rstrip() + f" 📅 {nxt.isoformat()}"
        nxt_line = DONE_RE.sub("", nxt_line).rstrip()
        new_lines.append(nxt_line)
    lines[line - 1:line] = new_lines
    _atomic_write(path, "\n".join(lines))
    return {"ok": True, "changed": True, "next": new_lines[1] if t.repeat else ""}


def main(argv: list[str]) -> int:
    try:
        if len(argv) in (2, 3) and argv[0] == "agenda":
            today = dt.date.fromisoformat(argv[2]) if len(argv) == 3 else dt.date.today()
            ag = agenda(collect(argv[1]), today)
            print(json.dumps({k: [vars(t) for t in v] for k, v in ag.items()}, ensure_ascii=False))
            return 0
        if len(argv) in (3, 4) and argv[0] == "complete":
            today = dt.date.fromisoformat(argv[3]) if len(argv) == 4 else dt.date.today()
            print(json.dumps(complete(argv[1], int(argv[2]), today), ensure_ascii=False))
            return 0
    except (OSError, ValueError) as e:
        print(json.dumps({"ok": False, "error": str(e)}, ensure_ascii=False))
        return 1
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
