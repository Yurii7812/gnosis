#!/usr/bin/env python3
"""指定日時のリマインダー・スヌーズ・再通知・通知履歴（TM03・TM05・TM14 の核）。

書き方（ふつうの Markdown。行のどこにあってもよい。タスクでなくてもよい）:
  - [ ] 薬を飲む ⏰ 2026-10-25 09:30      … その日時に知らせる（`remind:2026-10-25T09:30` でも可）
  - 歯医者の予約 ⏰ 2026-10-26             … 時刻を省くと 09:00
タスクが完了（`[x]`）になれば知らせない。コードブロックの中は無視。

ノートは書き換えない。扱い済み・スヌーズ・通知の履歴は `<vault>/.state/reminders.json`（派生・消えても元の印から作り直せる。
消えると履歴と「扱い済み」は失われ、過ぎた未完了のものが再び知らされる）。リマインダーの ID は（ファイル・文面・日時）から決めるので、行の位置が変わっても変わらない。
実際の通知（デスクトップ）は `notify` を渡したときだけ。既定では何も送らない。

CLI（JSON。--md なら Markdown）:
  reminders.py ROOT list [YYYY-MM-DDTHH:MM]              これから（と今の）リマインダー
  reminders.py ROOT fire [YYYY-MM-DDTHH:MM] [--notify]   時刻が来たものを「通知した」と記録して返す（再通知の間隔を過ぎたものも）
  reminders.py ROOT ack ID                                扱い済みにする（もう知らせない）
  reminders.py ROOT snooze ID [分] [YYYY-MM-DDTHH:MM]      分後まで知らせない（既定 10 分）
  reminders.py ROOT history [件数]                        通知の履歴と、通知したのに未処理のもの
"""
from __future__ import annotations

import datetime as dt
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import tasks as tk  # noqa: E402

MARK = re.compile(r"(?:⏰|\bremind:)\s*(\d{4}-\d{2}-\d{2})(?:[ T](\d{1,2}:\d{2}))?")
DEFAULT_TIME = "09:00"
RENOTIFY_MIN = 30          # 扱い済みにするまで、この間隔で再通知する
MAX_FIRES = 4              # 最初の通知 + 再通知 3 回まで（無限に鳴らさない）
FMT = "%Y-%m-%dT%H:%M"


def _id(file: str, text: str, at: str) -> str:
    return hashlib.sha1(f"{file}\0{text}\0{at}".encode("utf-8")).hexdigest()[:10]


def scan(root: str | Path) -> list[dict]:
    root = Path(root).resolve()
    out = []
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
                continue
            if fence:
                continue
            m = MARK.search(raw)
            if not m:
                continue
            hh, mm = (m.group(2) or DEFAULT_TIME).split(":")
            try:
                at = dt.datetime.strptime(f"{m.group(1)} {int(hh):02d}:{mm}", "%Y-%m-%d %H:%M")
            except ValueError:
                continue
            t = tk.parse_line(raw, rel, i)
            body = (t.text if t else raw.strip())
            body = MARK.sub("", body).strip(" -*")
            out.append({"id": _id(rel, body, at.strftime(FMT)), "file": rel, "line": i, "text": body or "(無題)", "at": at.strftime(FMT),
                        "task_done": bool(t and t.done)})
    return sorted(out, key=lambda r: (r["at"], r["file"], r["line"]))


def _state_path(root: Path) -> Path:
    return root / ".state" / "reminders.json"


def _load(root: Path) -> dict:
    try:
        d = json.loads(_state_path(root).read_text(encoding="utf-8"))
        d.setdefault("items", {})
        d.setdefault("history", [])
        return d
    except (OSError, ValueError):
        return {"items": {}, "history": []}


def _save(root: Path, st: dict) -> None:
    p = _state_path(root)
    p.parent.mkdir(parents=True, exist_ok=True)
    st["history"] = st["history"][-500:]
    tmp = p.with_name(p.name + ".tmp")
    tmp.write_text(json.dumps(st, ensure_ascii=False, indent=1), encoding="utf-8")
    os.replace(tmp, p)


def _now(s: str | None) -> dt.datetime:
    return dt.datetime.strptime(s, FMT) if s else dt.datetime.now().replace(second=0, microsecond=0)


def _status(r: dict, st: dict, now: dt.datetime) -> str:
    """done=不要（タスク完了・扱い済み）/ snoozed / due=いま知らせる / renotify=再通知待ち / waiting=まだ先 / exhausted=再通知を使い切った"""
    s = st["items"].get(r["id"], {})
    if r["task_done"] or s.get("acked"):
        return "done"
    at = dt.datetime.strptime(r["at"], FMT)
    if at > now:
        return "waiting"
    if s.get("snooze_until") and dt.datetime.strptime(s["snooze_until"], FMT) > now:
        return "snoozed"
    fires = s.get("fires", [])
    if not fires:
        return "due"
    if len(fires) >= MAX_FIRES:
        return "exhausted"
    last = dt.datetime.strptime(fires[-1], FMT)
    if s.get("snooze_until"):                               # スヌーズが明けたら、明けた時刻から再び知らせる
        return "due" if dt.datetime.strptime(s["snooze_until"], FMT) > last else "renotify" if now - last >= dt.timedelta(minutes=RENOTIFY_MIN) else "waiting_renotify"
    return "renotify" if now - last >= dt.timedelta(minutes=RENOTIFY_MIN) else "waiting_renotify"


def list_reminders(root: str | Path, now: str | None = None, days: int = 14) -> dict:
    root = Path(root).resolve()
    n = _now(now)
    st = _load(root)
    horizon = n + dt.timedelta(days=days)
    rows = []
    for r in scan(root):
        s = _status(r, st, n)
        at = dt.datetime.strptime(r["at"], FMT)
        if s == "done" or (s == "waiting" and at > horizon):
            continue
        rows.append({**r, "status": s, "fires": len(st["items"].get(r["id"], {}).get("fires", [])), "snooze_until": st["items"].get(r["id"], {}).get("snooze_until", "")})
    return {"now": n.strftime(FMT), "reminders": rows}


def fire(root: str | Path, now: str | None = None, notify=None) -> dict:
    """時刻が来た（due）ものと、再通知の間隔を過ぎた（renotify）ものを「通知した」と記録して返す。notify(reminder) を渡すと、そのときだけ実際に通知する。"""
    root = Path(root).resolve()
    n = _now(now)
    st = _load(root)
    fired = []
    for r in scan(root):
        s = _status(r, st, n)
        if s not in ("due", "renotify"):
            continue
        item = st["items"].setdefault(r["id"], {})
        item.setdefault("fires", []).append(n.strftime(FMT))
        ok = True
        if notify is not None:
            try:
                ok = notify(r) is not False
            except Exception:                              # 通知の失敗で記録を落とさない
                ok = False
        st["history"].append({"id": r["id"], "at": n.strftime(FMT), "text": r["text"], "file": r["file"], "kind": "再通知" if s == "renotify" else "通知", "delivered": ok if notify is not None else None})
        fired.append({**r, "status": s, "fire_no": len(item["fires"])})
    if fired:
        _save(root, st)
    return {"now": n.strftime(FMT), "fired": fired}


def _need(root: Path, rid: str) -> dict:
    for r in scan(root):
        if r["id"] == rid:
            return r
    raise ValueError("そのリマインダーはありません: " + rid)


def ack(root: str | Path, rid: str, now: str | None = None) -> dict:
    root = Path(root).resolve()
    r = _need(root, rid)
    st = _load(root)
    st["items"].setdefault(rid, {})["acked"] = _now(now).strftime(FMT)
    st["history"].append({"id": rid, "at": _now(now).strftime(FMT), "text": r["text"], "file": r["file"], "kind": "扱い済み", "delivered": None})
    _save(root, st)
    return {"id": rid, "acked": True}


def snooze(root: str | Path, rid: str, minutes: int = 10, now: str | None = None) -> dict:
    if minutes <= 0 or minutes > 60 * 24 * 14:
        raise ValueError("スヌーズは 1 分〜14 日の間で指定してください")
    root = Path(root).resolve()
    r = _need(root, rid)
    n = _now(now)
    until = (n + dt.timedelta(minutes=minutes)).strftime(FMT)
    st = _load(root)
    item = st["items"].setdefault(rid, {})
    item["snooze_until"] = until
    item["fires"] = []                                      # スヌーズが明けたら、もう一度最初から知らせる（再通知の回数も数え直す）
    st["history"].append({"id": rid, "at": n.strftime(FMT), "text": r["text"], "file": r["file"], "kind": f"スヌーズ（{until} まで）", "delivered": None})
    _save(root, st)
    return {"id": rid, "snooze_until": until}


def history(root: str | Path, limit: int = 50, now: str | None = None) -> dict:
    root = Path(root).resolve()
    st = _load(root)
    n = _now(now)
    unhandled = []
    for r in scan(root):
        s = st["items"].get(r["id"], {})
        if s.get("fires") and not s.get("acked") and not r["task_done"]:
            unhandled.append({**r, "fires": len(s["fires"]), "last": s["fires"][-1]})
    return {"history": list(reversed(st["history"]))[:limit], "unhandled": unhandled}


def desktop_notify(r: dict) -> bool:
    """notify-send があれば、デスクトップに通知する（ローカルのみ。外部通信なし）。無ければ False。"""
    exe = shutil.which("notify-send")
    if not exe:
        return False
    return subprocess.run([exe, "-a", "Gnosis", "リマインダー", f"{r['text']}\n{r['file']}"], timeout=10).returncode == 0


STATUS_LABEL = {"due": "今", "renotify": "再通知", "snoozed": "スヌーズ中", "waiting": "これから", "waiting_renotify": "通知済み（再通知待ち）", "exhausted": "再通知を使い切った（未処理）"}


def to_md(kind: str, r: dict) -> str:
    def link(f, ln):
        return f"[{f}:{ln}]({f.replace(' ', '%20')})"
    L: list[str] = []
    if kind == "list":
        L = [f"# リマインダー（{r['now'].replace('T', ' ')} 時点）", ""]
        for x in r["reminders"]:
            extra = f"・{x['snooze_until'].replace('T', ' ')} までスヌーズ" if x["snooze_until"] else ""
            L.append(f"- {x['at'].replace('T', ' ')} — {x['text']}（{STATUS_LABEL.get(x['status'], x['status'])}{extra}・{link(x['file'], x['line'])}・ID `{x['id']}`）")
        if not r["reminders"]:
            L.append("なし")
    elif kind == "history":
        L = ["# 通知の履歴", "", "## 通知したのに未処理", ""] + [f"- {x['text']}（{x['fires']} 回通知・最後 {x['last'].replace('T', ' ')}・{link(x['file'], x['line'])}・ID `{x['id']}`）" for x in r["unhandled"]]
        if not r["unhandled"]:
            L.append("なし")
        L += ["", "## 履歴", ""] + [f"- {h['at'].replace('T', ' ')} {h['kind']} — {h['text']}" + ("（届かなかった）" if h.get("delivered") is False else "") for h in r["history"]]
    elif kind == "fire":
        L = ["# 通知したリマインダー", ""] + [f"- {x['text']}（{x['fire_no']} 回目・{link(x['file'], x['line'])}）" for x in r["fired"]] + ([] if r["fired"] else ["なし"])
    return "\n".join(L) + "\n"


def main(argv: list[str]) -> int:
    try:
        md = "--md" in argv
        use_notify = "--notify" in argv
        a = [x for x in argv if x not in ("--md", "--notify")]
        root, cmd, rest = a[0], a[1], a[2:]
        if cmd == "list":
            r = list_reminders(root, rest[0] if rest else None)
        elif cmd == "fire":
            r = fire(root, rest[0] if rest else None, desktop_notify if use_notify else None)
        elif cmd == "ack":
            r = ack(root, rest[0])
        elif cmd == "snooze":
            r = snooze(root, rest[0], int(rest[1]) if len(rest) > 1 else 10, rest[2] if len(rest) > 2 else None)
        elif cmd == "history":
            r = history(root, int(rest[0]) if rest else 50)
        else:
            print(__doc__, file=sys.stderr)
            return 2
        print(to_md(cmd, r), end="") if md and cmd in ("list", "history", "fire") else print(json.dumps(r, ensure_ascii=False))
    except (OSError, ValueError, IndexError) as e:
        print(json.dumps({"error": str(e) or "引数が足りません"}, ensure_ascii=False))
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
