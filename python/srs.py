#!/usr/bin/env python3
"""間隔反復（SRS）・フラッシュカード・穴埋め・ランダム復習（LR02〜LR06・LR12）。

カードの原本はノート本文（Markdown）。復習の記録だけを <vault>/.gnosis/srs.json に持つ（派生データ。消してもカードは残る）。

カードの書き方（ノートのどこにでも。コードブロックの中は対象外）:
  Q: 質問                  ← 次の `A:` までが問い。`A:` から次の空行（か次の Q:）までが答え。複数行可
  A: 答え
  文の中の {{穴埋め}}      ← 穴埋め（Cloze）。`{{c1::語}}` と番号をつければ同じ文で番号ごとに別のカード（c1, c2…）
  {{答え::ヒント}}         ← ヒントつき
カード ID は「ノートのパス + 種類 + 内容のハッシュ」。ノートの本文を直すとカードの内容が変わり、新しいカードになる
（古い記録は残るが出題されない）。ノートの位置が変わっても内容が同じなら、パスが変わるので新規扱い。

スケジューラは SM-2 に準ずる（品質 0〜5。3 未満は忘れた扱いで翌日からやり直し）。
CLI（JSON）:
  srs.py ROOT scan                          カードの一覧（新規・期日・状態）
  srs.py ROOT due [YYYY-MM-DD] [--limit N]  今日の復習（期日が来たカード＋新規カード）
  srs.py ROOT answer CARD_ID 品質 [日付]     復習の記録（想起してから答えを見たあとに付ける。0〜5）
  srs.py ROOT random [N]                    ランダム復習（期日に関係なく無作為に N 枚）
  srs.py ROOT stats [日付]                  枚数と、期日別の数
"""
from __future__ import annotations

import datetime as dt
import hashlib
import json
import os
import random as _random
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

CLOZE_RE = re.compile(r"\{\{(?:c(\d+)::)?(.+?)(?:::(.+?))?\}\}")
STATE_VERSION = 1


def state_path(root: Path) -> Path:
    return root / ".gnosis" / "srs.json"


def load_state(root: Path) -> dict:
    p = state_path(root)
    if not p.exists():
        return {"version": STATE_VERSION, "cards": {}, "log": []}
    st = json.loads(p.read_text(encoding="utf-8"))
    if not isinstance(st, dict) or not isinstance(st.get("cards"), dict):
        raise ValueError("復習の記録が壊れています: " + str(p))
    st.setdefault("log", [])
    return st


def save_state(root: Path, st: dict) -> None:
    p = state_path(root)
    p.parent.mkdir(parents=True, exist_ok=True)
    tmp = p.with_name(p.name + ".gnosis-tmp")
    tmp.write_text(json.dumps(st, ensure_ascii=False, indent=1), encoding="utf-8")
    os.replace(tmp, p)


def _cid(path: str, kind: str, payload: str) -> str:
    return hashlib.sha1(f"{path}\0{kind}\0{payload}".encode("utf-8")).hexdigest()[:12]


def parse_cards(text: str, path: str) -> list[dict]:
    cards: list[dict] = []
    lines = text.split("\n")
    # front matter は読まない
    start = 0
    if lines and lines[0].strip() == "---":
        try:
            start = [x.strip() for x in lines[1:]].index("---") + 2
        except ValueError:
            start = 0
    fence = ""
    i = start
    while i < len(lines):
        ln = lines[i]
        s = ln.strip()
        if s.startswith(("```", "~~~")):
            mark = s[:3]
            fence = "" if fence == mark else (fence or mark)
            i += 1
            continue
        if fence:
            i += 1
            continue
        if s.startswith("Q:") or s.startswith("Ｑ:"):
            q = [s[2:].strip()]
            i += 1
            while i < len(lines) and not lines[i].strip().startswith(("A:", "Ａ:")) and lines[i].strip() and not lines[i].strip().startswith("Q:"):
                q.append(lines[i].strip())
                i += 1
            if i < len(lines) and lines[i].strip().startswith(("A:", "Ａ:")):
                a = [lines[i].strip()[2:].strip()]
                i += 1
                while i < len(lines) and lines[i].strip() and not lines[i].strip().startswith(("Q:", "Ｑ:")):
                    a.append(lines[i].strip())
                    i += 1
                front, back = "\n".join(q).strip(), "\n".join(a).strip()
                if front and back:
                    cards.append({"id": _cid(path, "qa", front + "\0" + back), "kind": "qa", "path": path, "line": i,
                                  "front": front, "back": back})
            continue
        if "{{" in ln:
            nums = sorted({int(m.group(1)) if m.group(1) else 0 for m in CLOZE_RE.finditer(ln)})
            for n in nums:
                def hide(m, n=n):
                    num = int(m.group(1)) if m.group(1) else 0
                    if num == n:
                        return "[" + (m.group(3) or "…") + "]"
                    return m.group(2)
                def reveal(m, n=n):
                    return ("**" + m.group(2) + "**") if (int(m.group(1)) if m.group(1) else 0) == n else m.group(2)
                front, back = CLOZE_RE.sub(hide, ln.strip()), CLOZE_RE.sub(reveal, ln.strip())
                cards.append({"id": _cid(path, f"cloze{n}", ln.strip()), "kind": "cloze", "path": path, "line": i + 1,
                              "front": front, "back": back})
        i += 1
    return cards


def collect(root: str | Path) -> list[dict]:
    root = Path(root)
    out: list[dict] = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if not d.startswith(".")]
        for name in sorted(filenames):
            if name.endswith(".md") and not name.startswith("."):
                p = Path(dirpath) / name
                try:
                    out += parse_cards(p.read_text(encoding="utf-8"), p.relative_to(root).as_posix())
                except (OSError, UnicodeDecodeError):
                    continue
    return out


def schedule(card: dict | None, quality: int, today: dt.date) -> dict:
    """SM-2。card は {ease, interval, reps, due, lapses}（新規なら None）。新しい状態を返す。"""
    if not 0 <= quality <= 5:
        raise ValueError("品質は 0〜5 です")
    ease = (card or {}).get("ease", 2.5)
    reps = (card or {}).get("reps", 0)
    interval = (card or {}).get("interval", 0)
    lapses = (card or {}).get("lapses", 0)
    if quality < 3:
        reps, interval, lapses = 0, 1, lapses + 1       # 忘れた: 翌日からやり直し（SM-2 の原典どおり ease は変えない）
    else:
        reps += 1
        interval = 1 if reps == 1 else 6 if reps == 2 else max(1, round(interval * ease))
        ease = max(1.3, ease + 0.1 - (5 - quality) * (0.08 + (5 - quality) * 0.02))
    return {"ease": round(ease, 3), "interval": interval, "reps": reps, "lapses": lapses,
            "due": (today + dt.timedelta(days=interval)).isoformat(), "last": today.isoformat()}


def status(card: dict, st: dict, today: dt.date) -> str:
    rec = st["cards"].get(card["id"])
    if rec is None:
        return "new"
    return "due" if rec["due"] <= today.isoformat() else "later"


def due(root: str | Path, today: dt.date, limit: int = 20, new_limit: int = 10) -> list[dict]:
    """今日の復習: 期日が来たカード（古い期日から）＋新規カード（new_limit まで）。"""
    root = Path(root)
    st = load_state(root)
    cards = collect(root)
    d = sorted((c for c in cards if status(c, st, today) == "due"), key=lambda c: (st["cards"][c["id"]]["due"], c["path"], c["line"]))
    n = [c for c in cards if status(c, st, today) == "new"][:new_limit]
    return (d + n)[:limit]


def answer(root: str | Path, card_id: str, quality: int, today: dt.date) -> dict:
    root = Path(root)
    if card_id not in {c["id"] for c in collect(root)}:
        raise ValueError("そのカードはありません（ノートが書き換わった可能性）: " + card_id)
    st = load_state(root)
    new = schedule(st["cards"].get(card_id), quality, today)
    st["cards"][card_id] = new
    st["log"].append({"id": card_id, "date": today.isoformat(), "q": quality})
    st["log"] = st["log"][-5000:]
    save_state(root, st)
    return new


def stats(root: str | Path, today: dt.date) -> dict:
    root = Path(root)
    st = load_state(root)
    cards = collect(root)
    by = {"new": 0, "due": 0, "later": 0}
    for c in cards:
        by[status(c, st, today)] += 1
    horizon: dict[str, int] = {}
    for c in cards:
        rec = st["cards"].get(c["id"])
        if rec and rec["due"] > today.isoformat():
            horizon[rec["due"]] = horizon.get(rec["due"], 0) + 1
    return {"cards": len(cards), **by, "upcoming": dict(sorted(horizon.items())),
            "reviewed_today": sum(1 for e in st["log"] if e["date"] == today.isoformat())}


def random_cards(root: str | Path, n: int = 5, seed: int | None = None) -> list[dict]:
    cards = collect(root)
    rng = _random.Random(seed)
    return rng.sample(cards, min(n, len(cards)))


def main(argv: list[str]) -> int:
    try:
        root = argv[0]
        cmd = argv[1] if len(argv) > 1 else ""
        today = dt.date.today()

        def day(i: int) -> dt.date:
            return dt.date.fromisoformat(argv[i]) if len(argv) > i and re.match(r"\d{4}-", argv[i]) else today
        if cmd == "scan":
            st = load_state(Path(root))
            print(json.dumps([{**c, "status": status(c, st, today)} for c in collect(root)], ensure_ascii=False))
        elif cmd == "due":
            lim = int(argv[argv.index("--limit") + 1]) if "--limit" in argv else 20
            print(json.dumps(due(root, day(2), lim), ensure_ascii=False))
        elif cmd == "answer" and len(argv) >= 4:
            print(json.dumps(answer(root, argv[2], int(argv[3]), day(4)), ensure_ascii=False))
        elif cmd == "random":
            print(json.dumps(random_cards(root, int(argv[2]) if len(argv) > 2 else 5), ensure_ascii=False))
        elif cmd == "stats":
            print(json.dumps(stats(root, day(2)), ensure_ascii=False))
        else:
            print(__doc__, file=sys.stderr)
            return 2
    except (OSError, ValueError) as e:
        print(json.dumps({"error": str(e)}, ensure_ascii=False))
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
