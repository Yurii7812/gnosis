#!/usr/bin/env python3
"""時間の記録・ポモドーロ・習慣・ライフログ（TM06・TM07・TM08・TM11 の PC 側の核）。

原本はノートの行（手書きでも、コマンドで追記しても同じ）。別の DB は持たない。印で始まる行を vault 全体から集める:
  - ⏱ 2026-10-21 09:00-09:25 仕事のメール #仕事 🍅1     … 時間の記録（終了が開始より前なら翌日。🍅N はポモドーロの完了数）
  - 🌱 運動 2026-10-21                                   … 習慣をやった日（同じ日・同じ名前は 1 回だけ数える）
  - 📋 2026-10-21 12:30 昼食 カレー                      … ライフログ（時刻は省略可）
コマンドで書くのは、記録用のノート（既定 `記録.md`）への**追記だけ**。既存の行は書き換えない。vault の外・ドット始まりには書かない。
タイマーの進行中の状態だけ `<vault>/.state/timer.json` に置く（消えたら進行中のタイマーが失われるだけで、記録済みの行は残る）。

CLI（JSON。--md なら Markdown）:
  tracker.py ROOT start 名前 [--pomodoro] [--at YYYY-MM-DDTHH:MM]   タイマー開始（--pomodoro は 25 分作業＋5 分休憩）
  tracker.py ROOT status [--at …]                                      進行中のタイマー（ポモドーロは今の局面と残り）
  tracker.py ROOT stop [--at …] [--file 記録.md]                       止めて、記録の行を追記（1 分未満は記録しない）
  tracker.py ROOT report 日|週|月|年 [YYYY-MM-DD]                      名前・タグごとの合計時間
  tracker.py ROOT habit check 名前 [YYYY-MM-DD] [--file 記録.md]       今日（または指定日）やったと記録（二重には書かない）
  tracker.py ROOT habit stats [名前] [YYYY-MM-DD]                      連続日数・達成率・直近 28 日
  tracker.py ROOT log 本文 [--at …] [--file 記録.md]                    ライフログを 1 行追記
  tracker.py ROOT day YYYY-MM-DD                                       その日の時間・習慣・ライフログをまとめる（日記へ貼れる Markdown）
"""
from __future__ import annotations

import datetime as dt
import json
import os
import re
import sys
from collections import defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import chrono as ch  # noqa: E402
import tasks as tk  # noqa: E402

FMT = "%Y-%m-%dT%H:%M"
DEFAULT_FILE = "記録.md"
WORK_MIN, BREAK_MIN, LONG_BREAK_MIN, LONG_EVERY = 25, 5, 15, 4

TIME_RE = re.compile(r"⏱\s*(\d{4}-\d{2}-\d{2})\s+(\d{1,2}:\d{2})\s*[-–~]\s*(\d{1,2}:\d{2})\s*(.*)$")
HABIT_RE = re.compile(r"🌱\s*(.+?)\s+(\d{4}-\d{2}-\d{2})\s*$")
LOG_RE = re.compile(r"📋\s*(\d{4}-\d{2}-\d{2})(?:\s+(\d{1,2}:\d{2}))?\s*(.*)$")
TAG_RE = re.compile(r"#([^\s#]+)")
POMO_RE = re.compile(r"🍅(\d+)")


def _t(day: str, hm: str) -> dt.datetime:
    h, m = hm.split(":")
    return dt.datetime.strptime(f"{day} {int(h):02d}:{m}", "%Y-%m-%d %H:%M")


def _now(s: str | None) -> dt.datetime:
    return dt.datetime.strptime(s, FMT) if s else dt.datetime.now().replace(second=0, microsecond=0)


def _lines(root: Path):
    for p in tk.iter_notes(root):
        try:
            text = p.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        rel = p.relative_to(root).as_posix()
        fence = False
        for i, raw in enumerate(text.split("\n"), 1):
            if raw.strip().startswith(("```", "~~~")):
                fence = not fence
            elif not fence:
                yield rel, i, raw


def entries(root: str | Path) -> dict:
    root = Path(root).resolve()
    times, habits, logs = [], {}, []
    for rel, i, raw in _lines(root):
        m = TIME_RE.search(raw)
        if m:
            start, end = _t(m.group(1), m.group(2)), _t(m.group(1), m.group(3))
            if end < start:
                end += dt.timedelta(days=1)
            rest = m.group(4)
            pm = POMO_RE.search(rest)
            label = POMO_RE.sub("", TAG_RE.sub("", rest)).strip()
            times.append({"file": rel, "line": i, "start": start.strftime(FMT), "end": end.strftime(FMT), "minutes": int((end - start).total_seconds() // 60),
                          "label": label or "(名前なし)", "tags": TAG_RE.findall(rest), "pomodoros": int(pm.group(1)) if pm else 0})
            continue
        m = HABIT_RE.search(raw)
        if m:
            habits.setdefault(m.group(1), set()).add(m.group(2))
            continue
        m = LOG_RE.search(raw)
        if m:
            logs.append({"file": rel, "line": i, "date": m.group(1), "time": m.group(2) or "", "text": m.group(3).strip()})
    return {"times": times, "habits": {k: sorted(v) for k, v in habits.items()}, "logs": logs}


# ---- 追記（記録用ノートへの追加だけ）----
def _target(root: Path, file: str) -> Path:
    t = (root / file).resolve()
    try:
        rel = t.relative_to(root)
    except ValueError:
        raise ValueError("vault の外には書きません") from None
    if any(p.startswith(".") for p in rel.parts) or t.suffix != ".md":
        raise ValueError("記録先は vault の中の .md ファイル（ドット始まりのフォルダ以外）にしてください")
    return t


def _append(root: Path, file: str, line: str, now: dt.datetime) -> str:
    t = _target(root, file)
    if t.exists():
        text = t.read_text(encoding="utf-8")
        if not text.endswith("\n"):
            text += "\n"
    else:
        title = t.stem
        text = f"---\ntime: {now:%Y-%m-%d %H:%M:%S}\ntitle: {title}\n---\n\n# {title}\n\n"
        t.parent.mkdir(parents=True, exist_ok=True)
    tmp = t.with_name(t.name + ".tmp")
    tmp.write_text(text + line + "\n", encoding="utf-8")
    os.replace(tmp, t)
    return t.relative_to(root).as_posix()


# ---- タイマー ----
def _timer_path(root: Path) -> Path:
    return root / ".state" / "timer.json"


def _load_timer(root: Path):
    try:
        return json.loads(_timer_path(root).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None


def start(root: str | Path, label: str, pomodoro: bool = False, now: str | None = None) -> dict:
    root = Path(root).resolve()
    if _load_timer(root):
        raise ValueError("すでにタイマーが動いています（先に stop）")
    label = label.strip()
    if not label or "\n" in label:
        raise ValueError("名前を 1 行で指定してください")
    st = {"label": label, "start": _now(now).strftime(FMT), "pomodoro": bool(pomodoro)}
    p = _timer_path(root)
    p.parent.mkdir(parents=True, exist_ok=True)
    tmp = p.with_name(p.name + ".tmp")
    tmp.write_text(json.dumps(st, ensure_ascii=False), encoding="utf-8")
    os.replace(tmp, p)
    return st


def _phase(elapsed_min: int) -> dict:
    """ポモドーロの局面。work 25 → break 5 を繰り返し、LONG_EVERY 回ごとの休憩は LONG_BREAK_MIN。"""
    pos, n = elapsed_min, 0
    while True:
        if pos < WORK_MIN:
            return {"phase": "work", "round": n + 1, "left": WORK_MIN - pos, "completed": n}
        pos -= WORK_MIN
        n += 1
        brk = LONG_BREAK_MIN if n % LONG_EVERY == 0 else BREAK_MIN
        if pos < brk:
            return {"phase": "break", "round": n, "left": brk - pos, "completed": n}
        pos -= brk


def status(root: str | Path, now: str | None = None) -> dict:
    root = Path(root).resolve()
    st = _load_timer(root)
    if not st:
        return {"running": False}
    n = _now(now)
    el = max(0, int((n - dt.datetime.strptime(st["start"], FMT)).total_seconds() // 60))
    out = {"running": True, "label": st["label"], "start": st["start"], "elapsed_min": el, "pomodoro": st["pomodoro"]}
    if st["pomodoro"]:
        out.update(_phase(el))
    return out


def stop(root: str | Path, now: str | None = None, file: str = DEFAULT_FILE) -> dict:
    root = Path(root).resolve()
    st = _load_timer(root)
    if not st:
        raise ValueError("動いているタイマーがありません")
    n = _now(now)
    s = dt.datetime.strptime(st["start"], FMT)
    el = int((n - s).total_seconds() // 60)
    _timer_path(root).unlink(missing_ok=True)
    if el < 1:
        return {"logged": False, "reason": "1 分未満なので記録しません", "minutes": el}
    tomatoes = _phase(el)["completed"] if st["pomodoro"] else 0
    # 作業の局面の途中で止めた場合の「完了数」は、休憩に入った分だけ（作業 25 分を満たしたもの）
    line = f"- ⏱ {s:%Y-%m-%d %H:%M}-{n:%H:%M} {st['label']}" + (f" 🍅{tomatoes}" if st["pomodoro"] else "")
    rel = _append(root, file, line, n)
    return {"logged": True, "file": rel, "line": line, "minutes": el, "pomodoros": tomatoes}


# ---- 集計 ----
def report(root: str | Path, period: str, on: dt.date) -> dict:
    root = Path(root).resolve()
    a, b = ch._range(period, on)
    by_label, by_tag = defaultdict(int), defaultdict(int)
    total, tomatoes, count = 0, 0, 0
    for e in entries(root)["times"]:
        d = e["start"][:10]
        if a.isoformat() <= d <= b.isoformat():
            by_label[e["label"]] += e["minutes"]
            for t in e["tags"]:
                by_tag[t] += e["minutes"]
            total += e["minutes"]; tomatoes += e["pomodoros"]; count += 1
    srt = lambda d: sorted(d.items(), key=lambda kv: (-kv[1], kv[0]))
    return {"from": a.isoformat(), "to": b.isoformat(), "total_min": total, "entries": count, "pomodoros": tomatoes, "by_label": srt(by_label), "by_tag": srt(by_tag)}


def _hm(m: int) -> str:
    return f"{m // 60} 時間 {m % 60} 分" if m >= 60 else f"{m} 分"


# ---- 習慣 ----
def habit_check(root: str | Path, name: str, day: str | None = None, file: str = DEFAULT_FILE, now: str | None = None) -> dict:
    root = Path(root).resolve()
    name = name.strip()
    if not name or "\n" in name or re.search(r"\s\d{4}-\d{2}-\d{2}$", name):
        raise ValueError("習慣の名前を日付なしの 1 行で指定してください")
    n = _now(now)
    day = day or n.strftime("%Y-%m-%d")
    dt.date.fromisoformat(day)
    if day in entries(root)["habits"].get(name, []):
        return {"added": False, "reason": "その日はもう記録されています", "name": name, "date": day}
    rel = _append(root, file, f"- 🌱 {name} {day}", n)
    return {"added": True, "name": name, "date": day, "file": rel}


def habit_stats(root: str | Path, name: str | None = None, today: dt.date | None = None) -> dict:
    root = Path(root).resolve()
    today = today or dt.date.today()
    hs = entries(root)["habits"]
    out = []
    for nm in sorted(hs) if name is None else [name]:
        days = set(hs.get(nm, []))
        if name is not None and nm not in hs:
            raise ValueError("その習慣の記録がありません: " + nm)
        ds = sorted(dt.date.fromisoformat(d) for d in days)
        # 連続日数: 今日まだなら昨日までを数える（今日これからやる余地を残す）
        cur, d = 0, today if today.isoformat() in days else today - dt.timedelta(days=1)
        while d.isoformat() in days:
            cur += 1; d -= dt.timedelta(days=1)
        longest = run = 0
        prev = None
        for x in ds:
            run = run + 1 if prev and (x - prev).days == 1 else 1
            longest = max(longest, run); prev = x
        rate = lambda n: round(sum(1 for i in range(n) if (today - dt.timedelta(days=i)).isoformat() in days) / n, 3)
        grid = "".join("■" if (today - dt.timedelta(days=i)).isoformat() in days else "□" for i in range(27, -1, -1))
        out.append({"name": nm, "total": len(days), "current_streak": cur, "longest_streak": longest, "rate_7": rate(7), "rate_30": rate(30), "last28": grid,
                    "done_today": today.isoformat() in days})
    return {"today": today.isoformat(), "habits": out}


# ---- ライフログ ----
def log_add(root: str | Path, text: str, at: str | None = None, file: str = DEFAULT_FILE) -> dict:
    root = Path(root).resolve()
    text = text.strip()
    if not text or "\n" in text:
        raise ValueError("本文を 1 行で指定してください")
    n = _now(at)
    rel = _append(root, file, f"- 📋 {n:%Y-%m-%d %H:%M} {text}", n)
    return {"added": True, "file": rel, "date": n.strftime("%Y-%m-%d"), "time": n.strftime("%H:%M")}


def day_summary(root: str | Path, day: str) -> dict:
    root = Path(root).resolve()
    dt.date.fromisoformat(day)
    e = entries(root)
    times = sorted((x for x in e["times"] if x["start"][:10] == day), key=lambda x: x["start"])
    habits = sorted(n for n, ds in e["habits"].items() if day in ds)
    logs = sorted((x for x in e["logs"] if x["date"] == day), key=lambda x: (x["time"], x["line"]))
    return {"date": day, "times": times, "total_min": sum(x["minutes"] for x in times), "habits": habits, "logs": logs}


def day_md(r: dict) -> str:
    L = [f"## {r['date']} の記録", ""]
    if r["times"]:
        L += [f"### 時間（合計 {_hm(r['total_min'])}）", ""] + [f"- {x['start'][11:]}–{x['end'][11:]} {x['label']}（{_hm(x['minutes'])}）" + (f" 🍅{x['pomodoros']}" if x["pomodoros"] else "") for x in r["times"]] + [""]
    if r["habits"]:
        L += ["### 習慣", ""] + [f"- ✔ {h}" for h in r["habits"]] + [""]
    if r["logs"]:
        L += ["### ライフログ", ""] + [f"- {(x['time'] + ' ') if x['time'] else ''}{x['text']}" for x in r["logs"]] + [""]
    if len(L) == 2:
        L.append("この日の記録はありません。")
    return "\n".join(L) + "\n"


def to_md(kind: str, r: dict) -> str:
    if kind == "status":
        if not r["running"]:
            return "タイマーは動いていません。\n"
        s = f"# 計測中: {r['label']}\n\n- 開始 {r['start'].replace('T', ' ')}・経過 {_hm(r['elapsed_min'])}\n"
        if r["pomodoro"]:
            s += f"- ポモドーロ {r['round']} 回目・{'作業' if r['phase'] == 'work' else '休憩'}中・あと {r['left']} 分（完了 {r['completed']} 回）\n"
        return s
    if kind == "report":
        L = [f"# 時間の記録 {r['from']}〜{r['to']}", "", f"合計 {_hm(r['total_min'])}（{r['entries']} 件・🍅{r['pomodoros']}）", "", "## 名前ごと", ""]
        L += [f"- {k}: {_hm(v)}" for k, v in r["by_label"]] or ["- なし"]
        L += ["", "## タグごと", ""] + ([f"- #{k}: {_hm(v)}" for k, v in r["by_tag"]] or ["- なし"])
        return "\n".join(L) + "\n"
    if kind == "stats":
        L = [f"# 習慣（{r['today']} 時点）", ""]
        for h in r["habits"]:
            L += [f"## {h['name']}" + ("　✔ 今日済み" if h["done_today"] else ""), "", f"- 連続 {h['current_streak']} 日（最長 {h['longest_streak']} 日）・合計 {h['total']} 日", f"- 達成率 直近 7 日 {int(h['rate_7'] * 100)}%・30 日 {int(h['rate_30'] * 100)}%",
                  f"- 直近 28 日 {h['last28']}", ""]
        return "\n".join(L if r["habits"] else L + ["記録がありません。"]) + "\n"
    if kind == "day":
        return day_md(r)
    return json.dumps(r, ensure_ascii=False, indent=1) + "\n"


def main(argv: list[str]) -> int:
    try:
        md = "--md" in argv
        opts, rest, it = {}, [], iter([x for x in argv if x != "--md"])
        for x in it:
            if x == "--pomodoro":
                opts["pomodoro"] = True
            elif x in ("--at", "--file"):
                opts[x[2:]] = next(it)
            else:
                rest.append(x)
        root, cmd, a = rest[0], rest[1], rest[2:]
        f = opts.get("file", DEFAULT_FILE)
        kind = cmd
        if cmd == "start":
            r = start(root, a[0], opts.get("pomodoro", False), opts.get("at"))
        elif cmd == "status":
            r = status(root, opts.get("at"))
        elif cmd == "stop":
            r = stop(root, opts.get("at"), f)
        elif cmd == "report":
            r = report(root, a[0], dt.date.fromisoformat(a[1]) if len(a) > 1 else dt.date.today())
        elif cmd == "habit" and a and a[0] == "check":
            r = habit_check(root, a[1], a[2] if len(a) > 2 else None, f)
        elif cmd == "habit" and a and a[0] == "stats":
            kind = "stats"
            nm = a[1] if len(a) > 1 and not re.fullmatch(r"\d{4}-\d{2}-\d{2}", a[1]) else None
            dstr = a[-1] if len(a) > 1 and re.fullmatch(r"\d{4}-\d{2}-\d{2}", a[-1]) else None
            r = habit_stats(root, nm, dt.date.fromisoformat(dstr) if dstr else None)
        elif cmd == "log":
            r = log_add(root, a[0], opts.get("at"), f)
        elif cmd == "day":
            r = day_summary(root, a[0])
        else:
            print(__doc__, file=sys.stderr)
            return 2
        print(to_md(kind, r), end="") if md else print(json.dumps(r, ensure_ascii=False))
    except (OSError, ValueError, IndexError) as e:
        print(json.dumps({"error": str(e) or "引数が足りません"}, ensure_ascii=False))
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
