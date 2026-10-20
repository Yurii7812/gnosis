#!/usr/bin/env python3
"""ノートのテンプレートと挿入メニュー（ED13）。

テンプレートは vault の `テンプレート/` フォルダ（`--dir` で変更可）に置いた、ふつうの .md ファイル。
本文に次の置き換え記号を書ける。**文字の置き換えだけで、式や命令は実行しない**（知らない `{{…}}` はそのまま残す）:
  {{date}} 2026-10-21   {{time}} 09:30   {{datetime}} 2026-10-21 09:30:00   {{weekday}} 水   {{year}} {{month}} {{day}}   {{title}} 新しいノートの題
  {{cursor}}            … 挿入後にカーソルを置く位置（1 つ目だけ。残りは消す）
`new` はテンプレートから新しいノートを作る（既存は上書きしない。vault の外・ドット始まりには作らない）。front matter が無いテンプレートには
`time:` と `title:` を足す。`render` は挿入用のテキストだけを返す（ノートには書かない）。

CLI（JSON）:
  templates.py ROOT list [--dir D]
  templates.py ROOT render NAME [--title T] [--now YYYY-MM-DDTHH:MM]     置き換え後のテキストとカーソル位置 {line,col}（1 から）
  templates.py ROOT new NAME NEWFILE [--title T] [--now …]
"""
from __future__ import annotations

import datetime as dt
import json
import os
import re
import sys
from pathlib import Path

DEFAULT_DIR = "テンプレート"
WEEK = "月火水木金土日"
MARK = re.compile(r"\{\{\s*(date|time|datetime|weekday|year|month|day|title|cursor)\s*\}\}")


def _dir(root: Path, d: str) -> Path:
    p = (root / d).resolve()
    try:
        p.relative_to(root)
    except ValueError:
        raise ValueError("テンプレートのフォルダが vault の外です") from None
    return p


def list_templates(root: str | Path, d: str = DEFAULT_DIR) -> dict:
    root = Path(root).resolve()
    base = _dir(root, d)
    items = []
    if base.is_dir():
        for p in sorted(base.rglob("*.md"), key=lambda q: (len(q.relative_to(base).parts), q.relative_to(base).as_posix())):   # 直下が先、サブフォルダは後
            items.append({"name": p.relative_to(base).with_suffix("").as_posix(), "path": p.relative_to(root).as_posix(), "chars": len(p.read_text(encoding="utf-8"))})
    return {"dir": d, "templates": items}


def _find(root: Path, d: str, name: str) -> Path:
    base = _dir(root, d)
    for cand in (base / (name + ".md"), base / name):
        if cand.is_file() and cand.resolve().is_relative_to(base):
            return cand
    raise ValueError("テンプレートが見つかりません: " + name)


def render(root: str | Path, name: str, title: str = "", now: dt.datetime | None = None, d: str = DEFAULT_DIR) -> dict:
    root = Path(root).resolve()
    text = _find(root, d, name).read_text(encoding="utf-8")
    now = now or dt.datetime.now()
    vals = {"date": f"{now:%Y-%m-%d}", "time": f"{now:%H:%M}", "datetime": f"{now:%Y-%m-%d %H:%M:%S}", "weekday": WEEK[now.weekday()],
            "year": f"{now:%Y}", "month": f"{now:%m}", "day": f"{now:%d}", "title": title}
    cursor = None
    out = []
    for ln, line in enumerate(text.split("\n"), 1):
        col_shift = 0
        pieces = []
        last = 0
        for m in MARK.finditer(line):
            pieces.append(line[last:m.start()])
            if m.group(1) == "cursor":
                if cursor is None:
                    cursor = (ln, len("".join(pieces)) + 1)
            else:
                pieces.append(vals[m.group(1)])
            last = m.end()
        pieces.append(line[last:])
        out.append("".join(pieces))
    return {"name": name, "text": "\n".join(out), "cursor": {"line": cursor[0], "col": cursor[1]} if cursor else None}


def new_note(root: str | Path, name: str, newfile: str, title: str = "", now: dt.datetime | None = None, d: str = DEFAULT_DIR) -> dict:
    root = Path(root).resolve()
    target = (root / newfile).resolve()
    try:
        rel = target.relative_to(root)
    except ValueError:
        raise ValueError("vault の外には作りません") from None
    if any(p.startswith(".") for p in rel.parts) or target.suffix != ".md":
        raise ValueError("作る場所は vault の中の .md（ドット始まりのフォルダ以外）にしてください")
    if target.exists():
        raise ValueError("すでにあります（上書きしません）: " + str(rel))
    now = now or dt.datetime.now()
    title = title or target.stem
    r = render(root, name, title, now, d)
    text = r["text"]
    if not text.startswith("---\n"):
        head = f"---\ntime: {now:%Y-%m-%d %H:%M:%S}\ntitle: {title}\n---\n\n"
        text = head + text
        if r["cursor"]:
            r["cursor"]["line"] += head.count("\n")
    target.parent.mkdir(parents=True, exist_ok=True)
    tmp = target.with_name(target.name + ".tmp")
    tmp.write_text(text, encoding="utf-8")
    os.replace(tmp, target)
    return {"path": rel.as_posix(), "cursor": r["cursor"]}


def main(argv: list[str]) -> int:
    try:
        opts, a, it = {}, [], iter(argv)
        for x in it:
            if x in ("--dir", "--title", "--now"):
                opts[x[2:]] = next(it)
            else:
                a.append(x)
        root, cmd, rest = a[0], a[1], a[2:]
        d = opts.get("dir", DEFAULT_DIR)
        now = dt.datetime.strptime(opts["now"], "%Y-%m-%dT%H:%M") if "now" in opts else None
        if cmd == "list":
            r = list_templates(root, d)
        elif cmd == "render":
            r = render(root, rest[0], opts.get("title", ""), now, d)
        elif cmd == "new":
            r = new_note(root, rest[0], rest[1], opts.get("title", ""), now, d)
        else:
            print(__doc__, file=sys.stderr)
            return 2
        print(json.dumps(r, ensure_ascii=False))
    except (OSError, ValueError, IndexError, StopIteration) as e:
        print(json.dumps({"error": str(e) or "引数が足りません"}, ensure_ascii=False))
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
