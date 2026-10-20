#!/usr/bin/env python3
"""一括変更の取引(UT13): 既存コマンドの前後でノートの内容を記録し、変わったファイルの一覧・差分・取り消しを出す。

begin  : vault のノート(.md。ドット始まりのフォルダは除く)の内容を `.gnosis/bulk/<id>/before/` に写して、取引を開始する。
end    : 開始時と比べ、変わった(modified)・増えた(added)・消えた(deleted)ファイルを数える。変わらなかった写しは捨てる。
status : 最新の取引の変更一覧と、各ファイルの差分の行数。
undo   : 最新の取引を取り消す(変わったファイルを元の内容に戻し、増えたファイルを消し、消えたファイルを戻す)。
         取引のあとで、さらに手で変えたファイルは上書きしない(--force で上書き)。取り消しは 1 回だけ。
list   : 取引の一覧(新しい順)。新しいものから 5 件だけ残す。
ノートの総量が 200 MB を超える vault では begin を断る(写しきれないため)。

CLI(JSON。--md なら Markdown):
  bulk.py ROOT begin LABEL | end ID | status [ID] | undo [ID] [--force] | list
"""
from __future__ import annotations

import datetime as dt
import difflib
import hashlib
import json
import os
import shutil
import sys
from pathlib import Path

KEEP = 5
LIMIT = 200 * 1024 * 1024


def _notes(root: Path):
    for p in sorted(root.rglob("*.md")):
        rel = p.relative_to(root)
        if not any(x.startswith(".") for x in rel.parts) and p.is_file():
            yield rel.as_posix(), p


def _h(p: Path) -> str:
    return hashlib.sha1(p.read_bytes()).hexdigest()


def _bulk(root: Path) -> Path:
    return root / ".gnosis" / "bulk"


def _write(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_bytes(data)
    os.replace(tmp, path)


def _jwrite(path: Path, obj) -> None:
    _write(path, json.dumps(obj, ensure_ascii=False).encode("utf-8"))


def _tx(root: Path, tid: str | None) -> tuple[Path, dict]:
    ids = sorted((d.name for d in _bulk(root).glob("*") if (d / "manifest.json").is_file()), reverse=True) if _bulk(root).is_dir() else []
    if tid is None:
        if not ids:
            raise ValueError("一括変更の記録がありません")
        tid = ids[0]
    if tid not in ids:
        raise ValueError("一括変更の記録が見つかりません: " + tid)
    d = _bulk(root) / tid
    return d, json.loads((d / "manifest.json").read_text(encoding="utf-8"))


def begin(root: str | Path, label: str, now: dt.datetime | None = None) -> dict:
    root = Path(root).resolve()
    files = list(_notes(root))
    if sum(p.stat().st_size for _, p in files) > LIMIT:
        raise ValueError("ノートの量が多すぎて(200 MB 超)、取り消せる形では実行できません")
    now = now or dt.datetime.now()
    tid = f"{now:%Y%m%dT%H%M%S}"
    while (_bulk(root) / tid).exists():
        tid += "x"
    d = _bulk(root) / tid
    before = {}
    for rel, p in files:
        data = p.read_bytes()
        _write(d / "before" / rel, data)
        before[rel] = hashlib.sha1(data).hexdigest()
    _jwrite(d / "manifest.json", {"id": tid, "label": label[:200], "started": now.isoformat(timespec="seconds"), "before": before, "state": "open"})
    for old in sorted((x.name for x in _bulk(root).glob("*") if x.is_dir()), reverse=True)[KEEP:]:
        shutil.rmtree(_bulk(root) / old, ignore_errors=True)
    return {"id": tid, "files": len(before)}


def end(root: str | Path, tid: str) -> dict:
    root = Path(root).resolve()
    d, m = _tx(root, tid)
    now = {rel: _h(p) for rel, p in _notes(root)}
    ch = {"modified": sorted(r for r in now if r in m["before"] and now[r] != m["before"][r]),
          "added": sorted(r for r in now if r not in m["before"]),
          "deleted": sorted(r for r in m["before"] if r not in now)}
    keep = set(ch["modified"]) | set(ch["deleted"])
    for rel in m["before"]:                               # 変わらなかった写しは捨てる
        if rel not in keep and (d / "before" / rel).exists():
            (d / "before" / rel).unlink()
    m.update({"state": "closed", "changes": ch, "after": {r: now[r] for r in ch["modified"] + ch["added"]}})
    m["before"] = {r: m["before"][r] for r in sorted(keep)}
    _jwrite(d / "manifest.json", m)
    return {"id": m["id"], "label": m["label"], **{k: len(v) for k, v in ch.items()}, "changes": ch}


def status(root: str | Path, tid: str | None = None) -> dict:
    root = Path(root).resolve()
    d, m = _tx(root, tid)
    if m["state"] == "open":
        raise ValueError("この取引はまだ終わっていません")
    ch = m.get("changes") or {"modified": [], "added": [], "deleted": []}
    det = []
    for rel in ch["modified"]:
        a = (d / "before" / rel).read_text(encoding="utf-8", errors="replace").split("\n")
        b = (root / rel).read_text(encoding="utf-8", errors="replace").split("\n") if (root / rel).exists() else []
        ud = list(difflib.unified_diff(a, b, lineterm="", n=0))
        add = sum(1 for x in ud if x.startswith("+") and not x.startswith("+++"))
        rem = sum(1 for x in ud if x.startswith("-") and not x.startswith("---"))
        det.append({"path": rel, "added_lines": add, "removed_lines": rem})
    return {"id": m["id"], "label": m["label"], "undone": bool(m.get("undone")), "modified": det, "added": ch["added"], "deleted": ch["deleted"]}


def undo(root: str | Path, tid: str | None = None, force: bool = False) -> dict:
    root = Path(root).resolve()
    d, m = _tx(root, tid)
    if m["state"] != "closed":
        raise ValueError("この取引はまだ終わっていません")
    if m.get("undone"):
        raise ValueError("この取引はもう取り消しました")
    ch = m["changes"]
    conflicts = []
    for rel in ch["modified"] + ch["added"]:             # 取引のあとで、さらに手で変えたものは上書きしない
        p = root / rel
        if p.exists() and _h(p) != m["after"][rel]:
            conflicts.append(rel)
    for rel in ch["deleted"]:
        if (root / rel).exists():
            conflicts.append(rel)
    if conflicts and not force:
        return {"undone": False, "conflicts": sorted(set(conflicts))}
    for rel in ch["modified"] + ch["deleted"]:
        _write(root / rel, (d / "before" / rel).read_bytes())
    for rel in ch["added"]:
        p = root / rel
        if p.exists():
            p.unlink()
    m["undone"] = True
    _jwrite(d / "manifest.json", m)
    return {"undone": True, "id": m["id"], "restored": len(ch["modified"]) + len(ch["deleted"]), "removed": len(ch["added"]), "forced": bool(conflicts)}


def list_tx(root: str | Path) -> dict:
    root = Path(root).resolve()
    out = []
    for d in sorted((x for x in _bulk(root).glob("*") if (x / "manifest.json").is_file()), reverse=True) if _bulk(root).is_dir() else []:
        m = json.loads((d / "manifest.json").read_text(encoding="utf-8"))
        ch = m.get("changes") or {}
        out.append({"id": m["id"], "label": m["label"], "state": m["state"], "undone": bool(m.get("undone")), "changed": sum(len(v) for v in ch.values())})
    return {"transactions": out}


def to_md(kind: str, r: dict) -> str:
    L: list[str] = []
    l = lambda p: f"[{p}]({p.replace(' ', '%20')})"
    if kind == "status":
        L = [f"# 一括変更: {r['label']}（{r['id']}）", ""] + (["取り消し済みです。", ""] if r["undone"] else [])
        L += [f"- 変わった {len(r['modified'])}・増えた {len(r['added'])}・消えた {len(r['deleted'])}", ""]
        L += [f"- {l(x['path'])}（+{x['added_lines']} −{x['removed_lines']} 行）" for x in r["modified"]]
        L += [f"- 増えた: {l(p)}" for p in r["added"]] + [f"- 消えた: {p}" for p in r["deleted"]]
    elif kind == "list":
        L = ["# 一括変更の記録", ""] + [f"- {t['id']} {t['label']}（変更 {t['changed']} 件" + ("・取り消し済み" if t["undone"] else "") + "）" for t in r["transactions"]]
        if not r["transactions"]:
            L.append("なし")
    return "\n".join(L) + "\n"


def main(argv: list[str]) -> int:
    try:
        md = "--md" in argv
        force = "--force" in argv
        a = [x for x in argv if x not in ("--md", "--force")]
        root, cmd, rest = a[0], a[1], a[2:]
        if cmd == "begin":
            r = begin(root, rest[0] if rest else "")
        elif cmd == "end":
            r = end(root, rest[0])
        elif cmd == "status":
            r = status(root, rest[0] if rest else None)
        elif cmd == "undo":
            r = undo(root, rest[0] if rest else None, force)
        elif cmd == "list":
            r = list_tx(root)
        else:
            print(__doc__, file=sys.stderr)
            return 2
        print(to_md(cmd, r), end="") if md and cmd in ("status", "list") else print(json.dumps(r, ensure_ascii=False))
    except (OSError, ValueError, IndexError, KeyError) as e:
        print(json.dumps({"error": str(e) or "引数が足りません"}, ensure_ascii=False))
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
