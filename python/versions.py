#!/usr/bin/env python3
"""ノート単位の版の履歴（ED10）: 保存・一覧・差分・復元。

版は vault の `.gnosis/versions/<ノートのパスの短い印>/<日時>-<内容の印>.md` に置く（ドット始まりなのでノートとして数えない）。
- save: 今の内容を 1 版として保存。直前の版と同じ内容なら足さない。1 ノートにつき 50 版まで（古いものから消す）。
- list: 新しい順。番号 1 が最新。
- diff N: 版 N と今の内容の差（unified diff）。
- restore N: 版 N の内容に戻す。**戻す前に今の内容を 1 版として保存する**ので、戻したあとでも元の内容に戻せる。書き込みは一時ファイル → 置き換え。
ノートの名前を変えると履歴の置き場所（パスで決まる）が変わる。rename は履歴を引き継がない（既知の制限）。

CLI（JSON。--md なら Markdown）:
  versions.py ROOT save NOTE | list NOTE | diff NOTE N | restore NOTE N
"""
from __future__ import annotations

import datetime as dt
import difflib
import hashlib
import json
import os
import re
import sys
from pathlib import Path

MAX_VERSIONS = 50


def _note(root: Path, name: str) -> tuple[Path, str]:
    p = (root / name).resolve()
    try:
        rel = p.relative_to(root)
    except ValueError:
        raise ValueError("vault の外は扱いません") from None
    if any(x.startswith(".") for x in rel.parts) or p.suffix != ".md" or not p.is_file():
        raise ValueError("vault の中のノートを指定してください: " + name)
    return p, rel.as_posix()


def _dir(root: Path, rel: str) -> Path:
    return root / ".gnosis" / "versions" / (hashlib.sha1(rel.encode("utf-8")).hexdigest()[:12])


def _entries(root: Path, rel: str) -> list[Path]:
    d = _dir(root, rel)
    return sorted((x for x in d.glob("*.md") if re.fullmatch(r"\d{8}T\d{6}-[0-9a-f]{8}\.md", x.name)), reverse=True) if d.is_dir() else []


def _write(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_bytes(data)
    os.replace(tmp, path)


def save(root: str | Path, name: str, now: dt.datetime | None = None) -> dict:
    root = Path(root).resolve()
    p, rel = _note(root, name)
    data = p.read_bytes()
    h = hashlib.sha1(data).hexdigest()[:8]
    ents = _entries(root, rel)
    if ents and ents[0].name.endswith(f"-{h}.md"):
        return {"saved": False, "reason": "直前の版と同じ内容です", "count": len(ents)}
    now = now or dt.datetime.now()
    newest = ents[0].name[:15] if ents else ""
    while f"{now:%Y%m%dT%H%M%S}" <= newest:      # 並びは日時順なので、同じ秒・過去にはならないよう 1 秒ずつ進める
        now += dt.timedelta(seconds=1)
    fn = _dir(root, rel) / f"{now:%Y%m%dT%H%M%S}-{h}.md"
    _write(fn, data)
    ents = _entries(root, rel)
    for old in ents[MAX_VERSIONS:]:
        old.unlink()
    return {"saved": True, "version": fn.name, "count": min(len(ents), MAX_VERSIONS)}


def list_versions(root: str | Path, name: str) -> dict:
    root = Path(root).resolve()
    p, rel = _note(root, name)
    cur = hashlib.sha1(p.read_bytes()).hexdigest()[:8]
    out = []
    for i, e in enumerate(_entries(root, rel), 1):
        m = re.match(r"(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})", e.name)
        out.append({"n": i, "when": f"{m[1]}-{m[2]}-{m[3]} {m[4]}:{m[5]}:{m[6]}", "bytes": e.stat().st_size, "same_as_current": e.name.endswith(f"-{cur}.md")})
    return {"note": rel, "versions": out}


def _pick(root: Path, rel: str, n: int) -> Path:
    ents = _entries(root, rel)
    if not 1 <= n <= len(ents):
        raise ValueError(f"版 {n} はありません（1〜{len(ents)}）" if ents else "このノートの履歴はありません")
    return ents[n - 1]


def diff(root: str | Path, name: str, n: int, context: int = 3) -> dict:
    root = Path(root).resolve()
    p, rel = _note(root, name)
    v = _pick(root, rel, n)
    a = v.read_text(encoding="utf-8", errors="replace").split("\n")
    b = p.read_text(encoding="utf-8", errors="replace").split("\n")
    d = list(difflib.unified_diff(a, b, f"版 {n}", "今", lineterm="", n=context))
    return {"note": rel, "n": n, "identical": a == b, "diff": d}


def restore(root: str | Path, name: str, n: int, now: dt.datetime | None = None) -> dict:
    root = Path(root).resolve()
    p, rel = _note(root, name)
    v = _pick(root, rel, n)
    data = v.read_bytes()
    if data == p.read_bytes():
        return {"restored": False, "reason": "すでにこの内容です", "note": rel}
    s = save(root, name, now)           # 戻す前の内容を残す(新しい版になるので、版の番号は 1 つずつずれる)
    _write(p, data)
    return {"restored": True, "note": rel, "from_n": n, "kept_current": s.get("saved", False)}


def to_md(kind: str, r: dict) -> str:
    if kind == "list":
        L = [f"# 版の履歴: {r['note']}", ""] + [f"{x['n']}. {x['when']}（{x['bytes']} バイト）" + ("・今と同じ" if x["same_as_current"] else "") for x in r["versions"]]
        return "\n".join(L + ([] if r["versions"] else ["なし（`:GnosisVersions save`）"])) + "\n"
    if kind == "diff":
        return "\n".join([f"# 版 {r['n']} と今の差: {r['note']}", "", "同じ内容です。" if r["identical"] else "```diff"] + ([] if r["identical"] else r["diff"] + ["```"])) + "\n"
    return json.dumps(r, ensure_ascii=False) + "\n"


def main(argv: list[str]) -> int:
    try:
        md = "--md" in argv
        a = [x for x in argv if x != "--md"]
        root, cmd, name = a[0], a[1], a[2]
        if cmd == "save":
            r = save(root, name)
        elif cmd == "list":
            r = list_versions(root, name)
        elif cmd == "diff":
            r = diff(root, name, int(a[3]))
        elif cmd == "restore":
            r = restore(root, name, int(a[3]))
        else:
            print(__doc__, file=sys.stderr)
            return 2
        print(to_md(cmd, r), end="") if md else print(json.dumps(r, ensure_ascii=False))
    except (OSError, ValueError, IndexError) as e:
        print(json.dumps({"error": str(e) or "引数が足りません"}, ensure_ascii=False))
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
