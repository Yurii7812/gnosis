#!/usr/bin/env python3
"""ブックマーク・最近のノート・知識リマインダー・時限の再提示・連想トレイル（SR12・SR13・TM15・XP04・XP13・XP16）。

原本はノートの記述と、利用者が作るデータ:
  ブックマーク … `<vault>/.gnosis/bookmarks.json`（利用者のデータ。スロット 1〜9 は「ハブ固定キー」）
  トレイル     … `<vault>/.gnosis/trails.json`（閲覧した順のノートの経路を名前をつけて保存／再生。Markdown ノートとして書き出して共有できる）
  ❓ 2027-01-01 半年後の自分はどう考えるか   … 未来への質問。日付が来ると「今日の問い」に出る（XP13）
  🕰 2027-01-01                              … タイムカプセル。その行を含むノートを、日付が来たら再提示（XP04）
  ? これは本当か / 仮説: …                    … 未解決の問いと仮説。`✅` を付けるか行を消すと解決済み。古いものを再提示（TM15）
ノートは書き換えない（`trail-export --write` が新しいノートを作るときだけ書く。既存は上書きしない）。

CLI（JSON。--md なら Markdown）:
  nav.py ROOT bookmark add NOTE [スロット1-9] | remove NOTE | list
  nav.py ROOT recent [modified|created] [件数]
  nav.py ROOT reminders [YYYY-MM-DD] [--days N]     未解決の問い・古い仮説・今日の問い・カプセル
  nav.py ROOT trail save 名前 NOTE… | add 名前 NOTE | show 名前 | list | remove 名前
  nav.py ROOT trail-export 名前 --write NEWFILE
"""
from __future__ import annotations

import datetime as dt
import json
import os
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import note_format_v2 as nf  # noqa: E402
import tasks as tk  # noqa: E402

FUTURE = re.compile(r"❓\s*(\d{4}-\d{2}-\d{2})\s+(.+)$")
CAPSULE = re.compile(r"🕰\s*(\d{4}-\d{2}-\d{2})")
OPEN_Q = re.compile(r"^\s*(?:[-*+]\s+)?(?:\?|？)\s*(.+)$")
HYPO = re.compile(r"^\s*(?:[-*+]\s+)?(?:仮説|Hypothesis)\s*[:：]\s*(.+)$", re.I)


def _atomic(path: Path, data) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(json.dumps(data, ensure_ascii=False, indent=1), encoding="utf-8")
    os.replace(tmp, path)


def _load(path: Path, default):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return default


def _find(root: Path, name: str) -> tuple[str, str]:
    """(相対パス, 題)。ファイル名・題・相対パスのどれでも引ける。"""
    for p in tk.iter_notes(root):
        rel = p.relative_to(root).as_posix()
        if rel == name or p.name == name or p.stem == name:
            return rel, nf._simple_parse_text(p, p.read_text(encoding="utf-8"))["title"]
    for p in tk.iter_notes(root):
        t = nf._simple_parse_text(p, p.read_text(encoding="utf-8"))["title"]
        if t == name:
            return p.relative_to(root).as_posix(), t
    raise ValueError("ノートが見つかりません: " + name)


# ---- ブックマーク ----
def _bm_path(root: Path) -> Path:
    return root / ".gnosis" / "bookmarks.json"


def bookmark_add(root: str | Path, note: str, slot: int | None = None) -> dict:
    root = Path(root).resolve()
    if slot is not None and not 1 <= slot <= 9:
        raise ValueError("スロットは 1〜9 です")
    rel, title = _find(root, note)
    st = _load(_bm_path(root), {"items": []})
    items = [i for i in st["items"] if i["path"] != rel]            # 同じノートは 1 件（スロットは付け替え）
    if slot is not None:
        for i in items:
            if i.get("slot") == slot:
                i.pop("slot")                                         # スロットの奪い合いは、あとから付けたほうが勝つ
    items.append({"path": rel, "title": title, **({"slot": slot} if slot else {})})
    _atomic(_bm_path(root), {"items": items})
    return {"path": rel, "slot": slot, "count": len(items)}


def bookmark_remove(root: str | Path, note: str) -> dict:
    root = Path(root).resolve()
    st = _load(_bm_path(root), {"items": []})
    try:
        rel, _ = _find(root, note)
    except ValueError:
        rel = note                                                    # ノートが消えていても、ブックマークは外せる
    items = [i for i in st["items"] if i["path"] != rel]
    if len(items) == len(st["items"]):
        raise ValueError("ブックマークにありません: " + note)
    _atomic(_bm_path(root), {"items": items})
    return {"removed": rel, "count": len(items)}


def bookmark_list(root: str | Path) -> dict:
    root = Path(root).resolve()
    items = _load(_bm_path(root), {"items": []})["items"]
    out = []
    for i in items:
        i = dict(i)
        i["exists"] = (root / i["path"]).is_file()                    # 消えた・動いたノートは印をつけて残す（勝手に消さない）
        out.append(i)
    out.sort(key=lambda i: (i.get("slot") is None, i.get("slot") or 0, i["title"]))
    return {"bookmarks": out}


def bookmark_slot(root: str | Path, slot: int) -> dict:
    for i in bookmark_list(root)["bookmarks"]:
        if i.get("slot") == slot:
            if not i["exists"]:
                raise ValueError("スロット %d のノートが見つかりません（%s）" % (slot, i["path"]))
            return i
    raise ValueError("スロット %d は空です" % slot)


# ---- 最近 ----
def recent(root: str | Path, by: str = "modified", limit: int = 20) -> dict:
    root = Path(root).resolve()
    if by not in ("modified", "created"):
        raise ValueError("modified か created を指定してください")
    rows = []
    for p in tk.iter_notes(root):
        text = p.read_text(encoding="utf-8")
        d = nf._simple_parse_text(p, text)
        tm = next((ln.split(":", 1)[1].strip() for ln in d["fm"] if ln.startswith("time:")), "")
        key = tm if by == "created" else dt.datetime.fromtimestamp(p.stat().st_mtime).strftime("%Y-%m-%d %H:%M:%S")
        if not key:
            continue
        rows.append({"path": p.relative_to(root).as_posix(), "title": d["title"], "when": key})
    rows.sort(key=lambda r: (r["when"], r["path"]), reverse=True)
    return {"by": by, "notes": rows[:max(1, limit)]}


# ---- 再提示 ----
def reminders(root: str | Path, today: dt.date | None = None, days: int = 90) -> dict:
    root = Path(root).resolve()
    today = today or dt.date.today()
    iso = today.isoformat()
    questions, hypotheses, future, capsules = [], [], [], []
    for p in tk.iter_notes(root):
        rel = p.relative_to(root).as_posix()
        text = p.read_text(encoding="utf-8")
        d = nf._simple_parse_text(p, text)
        age = (today - dt.date.fromtimestamp(p.stat().st_mtime)).days
        fence = False
        for i, raw in enumerate(text.split("\n"), 1):
            if raw.strip().startswith(("```", "~~~")):
                fence = not fence
                continue
            if fence:
                continue
            m = FUTURE.search(raw)
            if m:
                future.append({"file": rel, "line": i, "title": d["title"], "date": m.group(1), "text": m.group(2).strip(), "due": m.group(1) <= iso})
                continue
            m = CAPSULE.search(raw)
            if m:
                capsules.append({"file": rel, "line": i, "title": d["title"], "date": m.group(1), "due": m.group(1) <= iso})
                continue
            if "✅" in raw:
                continue
            m = OPEN_Q.match(raw)
            if m and len(m.group(1)) >= 4 and not raw.lstrip().startswith(("?[", "？[")):
                questions.append({"file": rel, "line": i, "title": d["title"], "text": m.group(1).strip(), "age_days": age})
                continue
            m = HYPO.match(raw)
            if m and age >= days:
                hypotheses.append({"file": rel, "line": i, "title": d["title"], "text": m.group(1).strip(), "age_days": age})
    srt = lambda xs, k: sorted(xs, key=k)
    return {"today": iso, "days": days,
            "questions": srt(questions, lambda x: (-x["age_days"], x["file"], x["line"])),
            "old_hypotheses": srt(hypotheses, lambda x: (-x["age_days"], x["file"], x["line"])),
            "future_due": srt([x for x in future if x["due"]], lambda x: (x["date"], x["file"])),
            "future_waiting": srt([x for x in future if not x["due"]], lambda x: (x["date"], x["file"])),
            "capsules_due": srt([x for x in capsules if x["due"]], lambda x: (x["date"], x["file"])),
            "capsules_waiting": srt([x for x in capsules if not x["due"]], lambda x: (x["date"], x["file"])),
            "note_text": "ノートの記述から拾っただけです。解決した問いは行に ✅ を付けるか消すと出なくなります。"}


# ---- トレイル ----
def _tr_path(root: Path) -> Path:
    return root / ".gnosis" / "trails.json"


def trail(root: str | Path, action: str, name: str | None = None, notes: list[str] | None = None) -> dict:
    root = Path(root).resolve()
    st = _load(_tr_path(root), {"trails": {}})
    if action == "list":
        return {"trails": [{"name": k, "steps": len(v)} for k, v in sorted(st["trails"].items())]}
    if not name or "\n" in name:
        raise ValueError("トレイルの名前を 1 行で指定してください")
    if action == "save":
        if not notes:
            raise ValueError("ノートを 1 つ以上指定してください")
        steps = []
        for n in notes:
            rel, title = _find(root, n)
            if not steps or steps[-1]["path"] != rel:                  # 連続した同じノートは 1 歩にまとめる
                steps.append({"path": rel, "title": title})
        st["trails"][name] = steps
        _atomic(_tr_path(root), st)
        return {"name": name, "steps": len(steps)}
    if action == "add":
        if name not in st["trails"]:
            raise ValueError("そのトレイルはありません: " + name)
        rel, title = _find(root, (notes or [""])[0])
        if not st["trails"][name] or st["trails"][name][-1]["path"] != rel:
            st["trails"][name].append({"path": rel, "title": title})
        _atomic(_tr_path(root), st)
        return {"name": name, "steps": len(st["trails"][name])}
    if action == "remove":
        if name not in st["trails"]:
            raise ValueError("そのトレイルはありません: " + name)
        del st["trails"][name]
        _atomic(_tr_path(root), st)
        return {"removed": name}
    if action == "show":
        if name not in st["trails"]:
            raise ValueError("そのトレイルはありません: " + name)
        return {"name": name, "steps": [{**s, "exists": (root / s["path"]).is_file()} for s in st["trails"][name]]}
    raise ValueError("save / add / show / list / remove のどれかです")


def trail_export(root: str | Path, name: str, newfile: str, now: dt.datetime | None = None) -> dict:
    root = Path(root).resolve()
    if not newfile:
        raise ValueError("書き出し先を --write NEWFILE で指定してください")
    t = trail(root, "show", name)
    target = (root / newfile).resolve()
    try:
        rel = target.relative_to(root)
    except ValueError:
        raise ValueError("vault の外には書きません") from None
    if any(p.startswith(".") for p in rel.parts) or target.suffix != ".md":
        raise ValueError("書き先は vault の中の .md（ドット始まりのフォルダ以外）にしてください")
    if target.exists():
        raise ValueError("すでにあります（上書きしません）: " + str(rel))
    now = now or dt.datetime.now()
    rel_dir = target.parent
    L = [f"---\ntime: {now:%Y-%m-%d %H:%M:%S}\ntitle: トレイル: {name}\n---\n\n# トレイル: {name}\n", "閲覧した順にたどった、ノートの経路です。\n"]
    for i, s in enumerate(t["steps"], 1):
        link = os.path.relpath(root / s["path"], rel_dir).replace(os.sep, "/").replace(" ", "%20")
        L.append(f"{i}. [{s['title']}]({link})" + ("" if s["exists"] else "（いまは見つかりません）"))
    target.parent.mkdir(parents=True, exist_ok=True)
    tmp = target.with_name(target.name + ".tmp")
    tmp.write_text("\n".join(L) + "\n", encoding="utf-8")
    os.replace(tmp, target)
    return {"written": rel.as_posix(), "steps": len(t["steps"])}


def _l(p, t=None):
    return f"[{t or p}]({p.replace(' ', '%20')})"


def to_md(kind: str, r: dict) -> str:
    L: list[str] = []
    if kind == "bookmark":
        L = ["# ブックマーク", ""] + [f"- {('[' + str(i['slot']) + '] ') if i.get('slot') else ''}{_l(i['path'], i['title'])}" + ("" if i["exists"] else "（見つかりません）") for i in r["bookmarks"]]
        if not r["bookmarks"]:
            L.append("なし（`:GnosisBookmark add`）")
    elif kind == "recent":
        L = [f"# 最近{'更新した' if r['by'] == 'modified' else '作った'}ノート", ""] + [f"- {x['when'][:16]} {_l(x['path'], x['title'])}" for x in r["notes"]]
    elif kind == "reminders":
        def sec(title, items, fmt):
            return [f"## {title}（{len(items)}）", ""] + ([fmt(x) for x in items[:30]] or ["なし"]) + [""]
        L = [f"# 知識リマインダー（{r['today']}）", ""]
        L += sec("今日の問い（未来への質問）", r["future_due"], lambda x: f"- {x['text']}（{x['date']} に書いた問い・{_l(x['file'], x['title'])}:{x['line']}）")
        L += sec("今日のカプセル", r["capsules_due"], lambda x: f"- {_l(x['file'], x['title'])}:{x['line']}（{x['date']}）")
        L += sec("未解決の問い", r["questions"], lambda x: f"- {x['text']}（{x['age_days']} 日更新なし・{_l(x['file'], x['title'])}:{x['line']}）")
        L += sec(f"{r['days']} 日以上たった仮説", r["old_hypotheses"], lambda x: f"- {x['text']}（{x['age_days']} 日・{_l(x['file'], x['title'])}:{x['line']}）")
        L += sec("これから届く問い・カプセル", r["future_waiting"] + r["capsules_waiting"], lambda x: f"- {x['date']} {x.get('text', '')} {_l(x['file'], x['title'])}")
        L.append(r["note_text"])
    elif kind == "trail":
        if "steps" in r and isinstance(r["steps"], list):
            L = [f"# トレイル: {r['name']}", ""] + [f"{i}. {_l(s['path'], s['title'])}" + ("" if s["exists"] else "（見つかりません）") for i, s in enumerate(r["steps"], 1)]
        else:
            L = ["# トレイル", ""] + [f"- {t['name']}（{t['steps']} 歩）" for t in r["trails"]]
    return "\n".join(L) + "\n"


def main(argv: list[str]) -> int:
    try:
        md = "--md" in argv
        write = None
        days = 90
        a = []
        it = iter([x for x in argv if x != "--md"])
        for x in it:
            if x == "--write":
                write = next(it)
            elif x == "--days":
                days = int(next(it))
            else:
                a.append(x)
        root, cmd, rest = a[0], a[1], a[2:]
        kind = cmd
        if cmd == "bookmark":
            act = rest[0]
            if act == "add":
                r = bookmark_add(root, rest[1], int(rest[2]) if len(rest) > 2 else None)
                kind = "json"
            elif act == "remove":
                r = bookmark_remove(root, rest[1]); kind = "json"
            elif act == "list":
                r = bookmark_list(root)
            elif act == "slot":
                r = bookmark_slot(root, int(rest[1])); kind = "json"
            else:
                raise ValueError("add / remove / list / slot のどれかです")
        elif cmd == "recent":
            by = rest[0] if rest and not rest[0].isdigit() else "modified"
            n = int(rest[-1]) if rest and rest[-1].isdigit() else 20
            r = recent(root, by, n)
        elif cmd == "reminders":
            r = reminders(root, dt.date.fromisoformat(rest[0]) if rest else None, days)
        elif cmd == "trail":
            r = trail(root, rest[0], rest[1] if len(rest) > 1 else None, rest[2:] if rest[0] == "save" else rest[2:3])
        elif cmd == "trail-export":
            r = trail_export(root, rest[0], write or ""); kind = "json"
        else:
            print(__doc__, file=sys.stderr)
            return 2
        print(to_md(kind, r), end="") if md and kind != "json" else print(json.dumps(r, ensure_ascii=False))
    except (OSError, ValueError, IndexError) as e:
        print(json.dumps({"error": str(e) or "引数が足りません"}, ensure_ascii=False))
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
