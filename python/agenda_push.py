#!/usr/bin/env python3
"""PC の Agenda（未完了のタスク）を、スマホのアプリへ渡す（TM16・TM17・TM18 の PC 側）。

アプリの `files/agenda.tsv` へ、USB（adb の run-as）で書く。タブ区切りの 1 ファイルで、アプリ（Kotlin）が依存なしで読める。
  # gnosis-agenda v1
  generated<TAB>2026-10-21T07:00
  task<TAB>キー<TAB>期限(YYYY-MM-DD か空)<TAB>時刻(HH:MM か空)<TAB>優先度(high|medium|low か空)<TAB>ノートの題<TAB>タスクの本文
キーは、ノートのパスとタスクの本文から決めた 10 桁（行が動いても変わらない。スマホで「完了」したタスクを PC が見つける目印。`agenda_pull.py`）。
未完了のタスクだけ（完了済み・開始日前・他のタスクを待っているものは除く）。期限の近い順・優先度順。最大 200 件。
本文のタブ・改行は空白にする。ノートの中身（タスク以外）は送らない。vault は読むだけ。書き込みは、アプリの files/agenda.tsv だけ（一時ファイル → mv）。

CLI:
  agenda_push.py ROOT show [YYYY-MM-DD]            送る内容を表示する（何も送らない）
  agenda_push.py ROOT write FILE [YYYY-MM-DD]      FILE に書く（試験・確認用。既存は上書きしない）
  agenda_push.py ROOT push [YYYY-MM-DD]            つながっているスマホのアプリへ送る
"""
from __future__ import annotations

import datetime as dt
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import note_format_v2 as nf  # noqa: E402
import tasks as tk  # noqa: E402

PACKAGE = "net.gnosis.capture"
MAX_TASKS = 200
HEADER = "# gnosis-agenda v1"


def _clean(s: str) -> str:
    return re.sub(r"[\t\r\n]+", " ", s).strip()


def task_key(file: str, text: str) -> str:
    """タスクの目印。ノートの相対パスとタスクの本文（印を除いたもの）から決める。行番号は含めない（行が動いても同じ）。"""
    import hashlib
    return hashlib.sha1((file + "\0" + _clean(text)).encode("utf-8")).hexdigest()[:10]


def reminds_text(reminds: list[int] | None) -> str:
    """"" = 書いていない(時刻ちょうど)・"none" = 通知なし・"1d,10m" = 期限の 1 日前と 10 分前。"""
    return "" if reminds is None else ("none" if not reminds else ",".join(tk.fmt_offset(m) for m in reminds))


def snapshot(root: str | Path, today: dt.date | None = None, now: dt.datetime | None = None) -> dict:
    root = Path(root).resolve()
    today = today or dt.date.today()
    now = now or dt.datetime.now()
    iso = today.isoformat()
    titles: dict[str, str] = {}
    rows = []
    for t in tk.collect(root):
        if t.done or t.blocked or (t.start and t.start > iso):
            continue
        if t.file not in titles:
            p = root / t.file
            titles[t.file] = nf._simple_parse_text(p, p.read_text(encoding="utf-8"))["title"]
        day = t.due or t.scheduled
        rows.append({"key": task_key(t.file, t.text), "due": day, "time": t.due_time if t.due else "", "priority": t.priority, "note": _clean(titles[t.file]), "text": _clean(t.text),
                     "duration": t.duration, "reminds": reminds_text(t.reminds), "repeat": _clean(t.repeat)})
    rank = {"high": 0, "medium": 1, "low": 2, "": 3}
    rows.sort(key=lambda r: (r["due"] or "9999-99-99", r["time"] or "99:99", rank[r["priority"]], r["note"], r["text"]))
    return {"generated": now.strftime("%Y-%m-%dT%H:%M"), "tasks": rows[:MAX_TASKS], "total_open": len(rows)}


def to_tsv(snap: dict) -> str:
    lines = [HEADER, f"generated\t{snap['generated']}"]
    for r in snap["tasks"]:
        # 7 列目までは v1 のまま。あとに 所要時間(分)・通知・繰り返し を足す(古いアプリは 7 列目までを読むので壊れない)
        lines.append("\t".join(["task", r["key"], r["due"], r["time"], r["priority"], r["note"], r["text"], str(r["duration"] or ""), r["reminds"], r["repeat"]]))
    return "\n".join(lines) + "\n"


def write(root: str | Path, out: str | Path, today: dt.date | None = None) -> dict:
    out = Path(out)
    if out.exists():
        raise ValueError("すでにあります（上書きしません）: " + str(out))
    snap = snapshot(root, today)
    tmp = out.with_name(out.name + ".tmp")
    tmp.write_text(to_tsv(snap), encoding="utf-8")
    os.replace(tmp, out)
    return {"path": str(out), "tasks": len(snap["tasks"]), "total_open": snap["total_open"]}


def _adb() -> str | None:
    return shutil.which("adb")


def push(root: str | Path, today: dt.date | None = None) -> dict:
    exe = _adb()
    if not exe:
        raise ValueError("adb が見つかりません")
    snap = snapshot(root, today)
    data = to_tsv(snap).encode("utf-8")
    r = subprocess.run([exe, "exec-in", "run-as", PACKAGE, "tee", "files/agenda.tsv.tmp"], input=data, capture_output=True, timeout=60)
    if r.returncode:
        raise ValueError("スマホへ送れませんでした（USB デバッグ・アプリのインストールを確認）: " + (r.stderr.decode("utf-8", "replace") or r.stdout.decode("utf-8", "replace"))[:160])
    m = subprocess.run([exe, "exec-out", "run-as", PACKAGE, "mv", "files/agenda.tsv.tmp", "files/agenda.tsv"], capture_output=True, timeout=60)
    if m.returncode:
        raise ValueError("スマホのファイルを置き換えられませんでした: " + (m.stderr.decode("utf-8", "replace") or "")[:160])
    return {"pushed": len(snap["tasks"]), "total_open": snap["total_open"], "bytes": len(data)}


def main(argv: list[str]) -> int:
    try:
        root, cmd, rest = argv[0], argv[1], argv[2:]
        def day(i):
            return dt.date.fromisoformat(rest[i]) if len(rest) > i else None
        if cmd == "show":
            r = snapshot(root, day(0))
            print(to_tsv(r), end="")
            return 0
        if cmd == "write":
            r = write(root, rest[0], day(1))
        elif cmd == "push":
            r = push(root, day(0))
        else:
            print(__doc__, file=sys.stderr)
            return 2
        print(json.dumps(r, ensure_ascii=False))
    except (OSError, ValueError, IndexError, subprocess.TimeoutExpired) as e:
        print(json.dumps({"error": str(e) or "引数が足りません"}, ensure_ascii=False))
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
