#!/usr/bin/env python3
"""スマホで「完了」したタスクと、スマホで編集したタスクの日時・通知などを、PC のノートへ反映する（TM16〜TM18 の PC 側）。

編集（`files/agenda-edit.tsv`。アプリが、タスクの画面で「保存」を押すと 1 行足す）:
  edit<TAB>キー<TAB>日付<TAB>時刻<TAB>所要時間(分)<TAB>通知<TAB>繰り返し<TAB>優先度
  通知は "" = 書かない(時刻ちょうど)・none = 通知なし・"1d,10m" = 期限の 1 日前と 10 分前。優先度は high / medium / low / ""。
  キーが一致する**未完了のタスク**の行の、`📅 日付 時刻`・`⌛`・`🔔`・`🔁`・優先度の印だけを書き換える（本文・ほかの印はそのまま。`tasks.edit_line`）。
  同じキーが複数あれば最後のものだけを反映する。値が正しくない行は反映せず「却下」と報告する。見つからないキーは「見つからない」。完了より先に反映する。

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


REPEATS = re.compile(r"^(|daily|weekly|monthly|yearly|weekday|every \d+ (?:days|weeks|months|years))$")


def parse_edits(text: str) -> tuple[list[dict], list[str]]:
    """(有効な編集(キーごとに最後のもの), 却下したキー)。"""
    by_key: dict[str, dict] = {}
    rejected: list[str] = []
    for ln in text.split("\n"):
        f = ln.rstrip("\r").split("\t")
        if len(f) < 8 or f[0] != "edit" or not KEY.match(f[1]):
            continue
        key, due, time, dur, rem, rep, prio = f[1], f[2], f[3], f[4], f[5], f[6], f[7]
        try:
            ok = ((due == "" or dt.date.fromisoformat(due) is not None) and re.fullmatch(r"\d{4}-\d{2}-\d{2}", due or "0000-00-00")
                  and (time == "" or re.fullmatch(r"([01]\d|2[0-3]):[0-5]\d", time)) and (dur == "" or (dur.isdigit() and 0 <= int(dur) <= 7 * 24 * 60))
                  and (rem in ("", "none") or re.fullmatch(r"\d+[mhd](,\d+[mhd])*", rem)) and REPEATS.match(rep) and prio in ("", "high", "medium", "low"))
        except ValueError:
            ok = False
        if not ok:
            rejected.append(key)
            by_key.pop(key, None)
            continue
        by_key[key] = {"key": key, "due": due, "time": time if due else "", "duration": int(dur or 0),
                       "reminds": None if rem == "" else ([] if rem == "none" else sorted({tk.parse_offset(v) for v in rem.split(",")}, reverse=True)),
                       "repeat": rep, "priority": prio}
    return list(by_key.values()), rejected


def apply_edits_text(root: str | Path, text: str) -> dict:
    root = Path(root).resolve()
    edits, rejected = parse_edits(text)
    if not edits and not rejected:
        return {"edited": [], "edit_missing": [], "edit_rejected": [], "edit_total": 0}
    open_tasks: dict[str, tk.Task] = {}
    for t in tk.collect(root):
        if not t.done:
            open_tasks.setdefault(ap.task_key(t.file, t.text), t)
    edited, missing = [], []
    for e in edits:
        t = open_tasks.get(e["key"])
        if t is None:
            missing.append(e["key"])
            continue
        p = root / t.file
        with open(p, encoding="utf-8", newline="") as fh:          # 改行(CRLF)をそのまま保つ
            raw_text = fh.read()
        lines = raw_text.split("\n")
        if t.line > len(lines) or not lines[t.line - 1].rstrip("\r").strip():
            missing.append(e["key"])
            continue
        cr = "\r" if lines[t.line - 1].endswith("\r") else ""
        old = lines[t.line - 1].rstrip("\r")
        new = tk.edit_line(old, due=e["due"], time=e["time"], duration=e["duration"], reminds=e["reminds"], repeat=e["repeat"], priority=e["priority"])
        if new != old:
            lines[t.line - 1] = new + cr
            tmp = p.with_name(p.name + ".tmp")
            with open(tmp, "w", encoding="utf-8", newline="") as fh:
                fh.write("\n".join(lines))
            tmp.replace(p)
        edited.append({"key": e["key"], "file": t.file, "text": t.text, "changed": new != old})
    return {"edited": edited, "edit_missing": missing, "edit_rejected": rejected, "edit_total": len(edits) + len(rejected)}


def _adb() -> str | None:
    return shutil.which("adb")


def _run_as(exe: str, *args: str, input: bytes | None = None) -> subprocess.CompletedProcess:
    return subprocess.run([exe, "exec-out", "run-as", PACKAGE, *args], input=input, capture_output=True, timeout=60)


def _drain(exe: str, root: str | Path, today: dt.date | None, stream: str = "done") -> dict | None:
    """phone の processing(done または edit)を読んで反映し、消す。無ければ None。"""
    name = f"files/agenda-{stream}.processing"
    r = _run_as(exe, "cat", name)
    if r.returncode != 0:
        return None
    text = r.stdout.decode("utf-8", "replace")
    res = apply_text(root, text, today) if stream == "done" else apply_edits_text(root, text)
    if _run_as(exe, "rm", "-f", name).returncode:
        raise ValueError("反映はできましたが、スマホ側の記録を消せませんでした（次回は同じ分が見つからないものとして報告されます）")
    return res


def _stream(exe: str, root: str | Path, today: dt.date | None, stream: str) -> list[dict]:
    results = []
    # 1) 前回止まって残っている processing を先に反映して消す（次の mv で上書きして失わないため）
    left = _drain(exe, root, today, stream)
    if left is not None:
        results.append(left)
    # 2) 新しい分を processing へ（アトミック。読んでいる間に増えた分は、次回の新しい分になる）→ 反映 → 消す
    _run_as(exe, "mv", f"files/agenda-{stream}.tsv", f"files/agenda-{stream}.processing")
    new = _drain(exe, root, today, stream)
    if new is not None:
        results.append(new)
    return results


def pull(root: str | Path, today: dt.date | None = None, refresh: bool = True) -> dict:
    exe = _adb()
    if not exe:
        raise ValueError("adb が見つかりません")
    edits = _stream(exe, root, today, "edit")          # 編集を先に(完了すると繰り返しの次の回が、編集した印を引き継ぐ)
    results = _stream(exe, root, today, "done")
    if not results and not edits:
        return {"applied": [], "missing": [], "total": 0, "edited": [], "note": "スマホに未反映の完了・編集はありません"}
    out = {"applied": [x for r in results for x in r["applied"]], "missing": [x for r in results for x in r["missing"]], "total": sum(r["total"] for r in results),
           "edited": [x for r in edits for x in r["edited"]], "edit_missing": [x for r in edits for x in r["edit_missing"]], "edit_rejected": [x for r in edits for x in r["edit_rejected"]]}
    if refresh:
        # 反映して記録を消すと、スマホは古い予定(agenda.tsv)を持ったまま完了済みを隠せなくなり、画面に復活して見える。
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
