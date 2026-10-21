#!/usr/bin/env python3
"""スマホで「完了」したタスクを、PC のノートへ反映する（TM17 の PC 側）。

スマホのアプリは、通知や予定の画面で「完了」を押すと、`files/agenda-done.tsv` に 1 行足す（ノートそのものは持っていないので、書き換えられない）:
  done<TAB>キー<TAB>2026-10-21T09:12
PC がそれを読み、キー（`agenda_push.task_key`: ノートのパス + タスクの本文）が一致する**未完了のタスク**を、`tasks.complete`（繰り返しは次の回を作る）で完了にする。
  - 見つからない（すでに完了・本文を書き換えた・ノートを消した）キーは、何も書かず「見つからない」と報告する。
  - 同じキーが複数あっても、1 回の反映につき 1 つだけ完了にする。同じキーが何度書かれていても、二重には完了しない（冪等）。
  - ノートへの書き込みは、タスクの完了の印（`[x]`・`✅ 日付`・繰り返しの次の回）だけ。
スマホ側のファイルは、まず前回止まって残った `agenda-done.processing` を反映して消し、そのあと新しい `agenda-done.tsv` を `agenda-done.processing` へ名前を変えてから読み（読んでいる間に増えた分を失わない）、反映できたら消す。

CLI（JSON）:
  agenda_pull.py ROOT apply FILE        FILE（スマホの agenda-done.tsv と同じ形）を反映する（試験・手動用）
  agenda_pull.py ROOT pull              つながっているスマホから取って反映する
"""
from __future__ import annotations

import datetime as dt
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import agenda_push as ap  # noqa: E402
import tasks as tk  # noqa: E402

PACKAGE = ap.PACKAGE
KEY = re.compile(r"^[0-9a-f]{10}$")


def parse(text: str) -> list[dict]:
    out, seen = [], set()
    for ln in text.split("\n"):
        f = ln.rstrip("\r").split("\t")
        if len(f) >= 2 and f[0] == "done" and KEY.match(f[1]) and f[1] not in seen:
            seen.add(f[1])
            out.append({"key": f[1], "at": f[2] if len(f) > 2 else ""})
    return out


def apply_text(root: str | Path, text: str, today: dt.date | None = None) -> dict:
    root = Path(root).resolve()
    today = today or dt.date.today()
    wanted = parse(text)
    if not wanted:
        return {"applied": [], "missing": [], "total": 0}
    open_tasks: dict[str, tk.Task] = {}
    for t in tk.collect(root):
        if not t.done:
            open_tasks.setdefault(ap.task_key(t.file, t.text), t)
    applied, missing = [], []
    for w in wanted:
        t = open_tasks.get(w["key"])
        if t is None:
            missing.append(w["key"])
            continue
        r = tk.complete(root / t.file, t.line, today)
        if r.get("ok") and r.get("changed"):
            applied.append({"key": w["key"], "file": t.file, "text": t.text, "next": r.get("next", "")})
        else:
            missing.append(w["key"])
    return {"applied": applied, "missing": missing, "total": len(wanted)}


def _adb() -> str | None:
    return shutil.which("adb")


def _run_as(exe: str, *args: str, input: bytes | None = None) -> subprocess.CompletedProcess:
    return subprocess.run([exe, "exec-out", "run-as", PACKAGE, *args], input=input, capture_output=True, timeout=60)


def _drain(exe: str, root: str | Path, today: dt.date | None) -> dict | None:
    """phone の processing を読んで反映し、消す。無ければ None。"""
    r = _run_as(exe, "cat", "files/agenda-done.processing")
    if r.returncode != 0:
        return None
    res = apply_text(root, r.stdout.decode("utf-8", "replace"), today)
    if _run_as(exe, "rm", "-f", "files/agenda-done.processing").returncode:
        raise ValueError("反映はできましたが、スマホ側の記録を消せませんでした（次回は同じ分が見つからないものとして報告されます）")
    return res


def pull(root: str | Path, today: dt.date | None = None, refresh: bool = True) -> dict:
    exe = _adb()
    if not exe:
        raise ValueError("adb が見つかりません")
    results = []
    # 1) 前回止まって残っている processing を先に反映して消す（次の mv で上書きして失わないため）
    left = _drain(exe, root, today)
    if left is not None:
        results.append(left)
    # 2) 新しい分を processing へ（アトミック。読んでいる間に増えた分は、次回の新しい分になる）→ 反映 → 消す
    _run_as(exe, "mv", "files/agenda-done.tsv", "files/agenda-done.processing")
    new = _drain(exe, root, today)
    if new is not None:
        results.append(new)
    if not results:
        return {"applied": [], "missing": [], "total": 0, "note": "スマホに未反映の完了はありません"}
    out = {"applied": [x for r in results for x in r["applied"]], "missing": [x for r in results for x in r["missing"]], "total": sum(r["total"] for r in results)}
    if refresh:
        # 反映して完了の記録を消すと、スマホは古い予定(agenda.tsv)を持ったまま完了済みを隠せなくなり、画面に復活して見える。
        # 反映後の最新の予定を送り直す(失敗しても反映は済んでいるので、結果に書くだけ)
        try:
            out["refreshed"] = ap.push(root, today)["pushed"]
        except (ValueError, OSError, subprocess.SubprocessError) as e:
            out["refresh_error"] = str(e)[:200]
    return out


def main(argv: list[str]) -> int:
    try:
        root, cmd, rest = argv[0], argv[1], argv[2:]
        if cmd == "apply":
            r = apply_text(root, Path(rest[0]).read_text(encoding="utf-8"))
        elif cmd == "pull":
            r = pull(root, refresh="--no-refresh" not in rest)
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
