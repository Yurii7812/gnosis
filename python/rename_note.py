#!/usr/bin/env python3
"""ノートの名前変更・移動と、参照の安全な更新（UT03）。取り消し・試走（dry-run）つき。

  - 他のノートの `[文字](相手.md)` / `[文字](相手.md#見出し)` / `![](画像)` のうち、このノートを指すものを新しい場所に書き換える。
    リンクの書き方（`%20` の有無、`#見出し`、タイトル属性 `"…"`）は保つ。コードブロックの中は触らない。URL（`://`・`mailto:`）と `#` だけのリンクも触らない。
  - 別のフォルダへ移すときは、移したノート自身の相対リンク（他のノート・画像）も新しい場所から計算し直す。
  - スマホの取り込み記録（`.state/capture_imported.json` の ids）がこのノートを指していれば、新しい場所に付け替える（二重取り込みを防ぐ）。
  - 変えるファイルは変える前に `.state/rename-undo/<日時>/` に控える。`undo` で元に戻せる（そのあとに変わったファイルがあれば `--force`）。
  - vault の外・ドット始まりのフォルダ・.md 以外・すでにあるファイルへは移さない。失敗したときは何も変えない。

CLI（1 行の JSON）:
  rename_note.py rename ROOT OLD NEW [--dry-run]
  rename_note.py undo ROOT [--force]
  rename_note.py last ROOT
"""
from __future__ import annotations

import hashlib
import json
import os
import re
import shutil
import sys
import time
from pathlib import Path
from urllib.parse import quote, unquote

LINK = re.compile(r"(!?)\[((?:\\.|[^\]\\])*)\]\(([^)\s]+)((?:\s+\"[^\"]*\")?)\)")
CAPTURE_STATE = ".state/capture_imported.json"
UNDO_DIR = ".state/rename-undo"


def _sha(p: Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()


def _is_url(t: str) -> bool:
    return t.startswith("#") or "://" in t or t.lower().startswith(("mailto:", "tel:", "data:"))


def _split(t: str) -> tuple[str, str]:
    for i, ch in enumerate(t):
        if ch in "#?":
            return t[:i], t[i:]
    return t, ""


def _fmt(newrel: str, orig: str) -> str:
    return quote(newrel, safe="/") if "%" in orig else newrel.replace(" ", "%20")


def _rewrite(text: str, here_old: Path, here_new: Path, old: Path, new: Path, moved: bool) -> tuple[str, list[dict]]:
    """here_old: このファイルの元の場所、here_new: 書いたあとの場所(移さないファイルでは同じ)。"""
    out, changes, fence = [], [], False
    for ln_no, line in enumerate(text.split("\n"), 1):
        if line.strip().startswith(("```", "~~~")):
            fence = not fence
            out.append(line)
            continue
        if fence:
            out.append(line)
            continue
        def sub(m):
            bang, label, target, title = m.group(1), m.group(2), m.group(3), m.group(4)
            if _is_url(target):
                return m.group(0)
            path, rest = _split(target)
            if not path:
                return m.group(0)
            dest = (here_old.parent / unquote(path)).resolve()
            if dest == old:
                dest = new
            elif not moved:
                return m.group(0)                         # 移していないファイルは、このノートを指すリンクだけ直す
            rel = os.path.relpath(dest, here_new.parent).replace(os.sep, "/")
            newt = _fmt(rel, path) + rest
            if newt == target:
                return m.group(0)
            changes.append({"line": ln_no, "from": target, "to": newt})
            return f"{bang}[{label}]({newt}{title})"
        out.append(LINK.sub(sub, line))
    return "\n".join(out), changes


def _check_paths(root: Path, old: str, new: str) -> tuple[Path, Path]:
    op, np_ = (root / old).resolve(), (root / new).resolve()
    for p, what in ((op, "元"), (np_, "移し先")):
        try:
            rel = p.relative_to(root)
        except ValueError:
            raise ValueError(f"{what}が vault の外です") from None
        if any(part.startswith(".") for part in rel.parts):
            raise ValueError(f"{what}がドット始まりのフォルダです")
    if not op.is_file() or op.suffix != ".md":
        raise ValueError("元のノート（.md）がありません: " + old)
    if np_.suffix != ".md":
        raise ValueError("新しい名前は .md にしてください")
    if np_ == op:
        raise ValueError("名前が同じです")
    if np_.exists():
        raise ValueError("すでにあります（上書きしません）: " + new)
    return op, np_


def rename(root: str | Path, old: str, new: str, dry_run: bool = False) -> dict:
    root = Path(root).resolve()
    op, np_ = _check_paths(root, old, new)
    moved = op.parent != np_.parent
    plan: dict[Path, tuple[str, str, list[dict]]] = {}                 # ファイル(元の場所) → (元の本文, 新しい本文, 変更)
    for p in sorted(root.rglob("*.md")):
        if any(part.startswith(".") for part in p.relative_to(root).parts):
            continue
        try:
            text = p.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        if p == op:
            new_text, ch = _rewrite(text, op, np_, op, np_, moved)
        else:
            new_text, ch = _rewrite(text, p, p, op, np_, False)
        if ch:
            plan[p] = (text, new_text, ch)
    # スマホの取り込み記録
    st_path = root / CAPTURE_STATE
    st_new, st_changes = None, []
    if st_path.is_file():
        try:
            st = json.loads(st_path.read_text(encoding="utf-8"))
            r_old, r_new = op.relative_to(root).as_posix(), np_.relative_to(root).as_posix()
            for k, v in list(st.get("ids", {}).items()):
                base, _, frag = v.partition("#")
                if base == r_old:
                    st["ids"][k] = r_new + ("#" + frag if frag else "")
                    st_changes.append(k)
            if st_changes:
                st_new = json.dumps(st, ensure_ascii=False, indent=1)
        except (ValueError, AttributeError):
            pass                                                       # 壊れた記録には触らない
    summary = {"ok": True, "dry_run": dry_run, "old": op.relative_to(root).as_posix(), "new": np_.relative_to(root).as_posix(), "moved_folder": moved,
               "updated": [{"file": (np_ if p == op else p).relative_to(root).as_posix(), "changes": ch} for p, (_, _, ch) in plan.items()],
               "capture_ids": len(st_changes)}
    summary["links_updated"] = sum(len(u["changes"]) for u in summary["updated"])
    if dry_run:
        return summary
    stamp = time.strftime("%Y%m%d-%H%M%S")
    bdir = root / UNDO_DIR / stamp
    n = 2
    while bdir.exists():
        bdir = root / UNDO_DIR / f"{stamp}-{n}"; n += 1
    saved = [op] + [p for p in plan if p != op] + ([st_path] if st_new is not None else [])
    for p in saved:
        rel = p.relative_to(root)
        (bdir / "files" / rel).parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(p, bdir / "files" / rel)
    np_.parent.mkdir(parents=True, exist_ok=True)
    try:
        os.replace(op, np_)
        for p, (_, t, _) in plan.items():
            target = np_ if p == op else p
            tmp = target.with_name(target.name + ".tmp")
            tmp.write_text(t, encoding="utf-8")
            os.replace(tmp, target)
        if st_new is not None:
            st_path.write_text(st_new, encoding="utf-8")
    except OSError:
        # 途中で失敗したら、控えから元に戻す
        for p in saved:
            shutil.copy2(bdir / "files" / p.relative_to(root), p)
        np_.unlink(missing_ok=True)
        raise
    meta = {"old": summary["old"], "new": summary["new"], "files": [p.relative_to(root).as_posix() for p in saved],
            "after": {(np_ if p == op else p).relative_to(root).as_posix(): _sha(np_ if p == op else p) for p in saved if p != st_path}}
    if st_new is not None:
        meta["after"][CAPTURE_STATE] = _sha(st_path)
    (bdir / "meta.json").write_text(json.dumps(meta, ensure_ascii=False), encoding="utf-8")
    summary["undo"] = bdir.name
    return summary


def _last(root: Path):
    base = root / UNDO_DIR
    ds = sorted(d for d in base.iterdir() if not d.name.endswith(".done") and (d / "meta.json").is_file()) if base.is_dir() else []
    return ds[-1] if ds else None


def last(root: str | Path) -> dict:
    d = _last(Path(root).resolve())
    if not d:
        return {"ok": False}
    m = json.loads((d / "meta.json").read_text(encoding="utf-8"))
    return {"ok": True, "undo": d.name, "old": m["old"], "new": m["new"], "files": len(m["files"])}


def undo(root: str | Path, force: bool = False) -> dict:
    root = Path(root).resolve()
    d = _last(root)
    if not d:
        return {"ok": False, "error": "取り消せる名前変更がありません"}
    m = json.loads((d / "meta.json").read_text(encoding="utf-8"))
    changed = [r for r, h in m["after"].items() if not (root / r).is_file() or _sha(root / r) != h]
    if changed and not force:
        return {"ok": False, "error": "名前変更のあとに変わったファイルがあります（--force で元に戻す）", "changed": changed}
    if (root / m["old"]).exists() and not force:
        return {"ok": False, "error": "元の名前のファイルがすでにあります: " + m["old"]}
    for r in m["files"]:
        src = d / "files" / r
        dest = root / r
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dest)
    (root / m["new"]).unlink(missing_ok=True)
    shutil.move(str(d), str(d.with_name(d.name + ".done")))
    return {"ok": True, "restored": m["files"], "removed": m["new"]}


def main(argv: list[str]) -> int:
    try:
        flags = {x for x in argv if x.startswith("--")}
        a = [x for x in argv if not x.startswith("--")]
        if len(a) == 4 and a[0] == "rename":
            r = rename(a[1], a[2], a[3], "--dry-run" in flags)
        elif len(a) == 2 and a[0] == "undo":
            r = undo(a[1], "--force" in flags)
        elif len(a) == 2 and a[0] == "last":
            r = last(a[1])
        else:
            print(__doc__, file=sys.stderr)
            return 2
        print(json.dumps(r, ensure_ascii=False))
        return 0 if r.get("ok", True) else 1
    except (OSError, ValueError) as e:
        print(json.dumps({"ok": False, "error": str(e)}, ensure_ascii=False))
        return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
