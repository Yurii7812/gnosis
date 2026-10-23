#!/usr/bin/env python3
"""ノートの分割（ED06）と、その取り消し。

元ノート（SRC）の一つの節（見出し 1 つ分）を、同じフォルダの新しいノート（NEWFILE）に切り出す。

  - 切り出す範囲: その見出しの行から、同じかより上の階層の次の見出し（またはファイル末尾の関係ブロック `ParentBranch:` など）の手前まで。
    コードブロックの中の `#` は見出しではない。ノートの題（H1）は分割できない。
  - 新しいノート: front matter（time・title=見出しの文字）、`# 見出し`、切り出した本文、最後に `Related:` で元ノートへのリンク。
    `Related:` を選ぶのは、親子（ParentBranch）にすると Folgezettel の番号の振り直しに波及するため（対称で副作用が小さい）。
  - 元ノート: 見出しは残し、本文を `→ [見出し](新ノート.md)（分割しました）` に置き換える。元ノートのファイルは消えないので、
    元ノートを指す既存のリンクは壊れない。`元ノート.md#見出し` を指すリンクは、新しいノートを指すように書き換える。
  - 変えるファイルは変える前に `.state/split-undo/<日時>/` に控える。`undo` で元に戻せる（分割のあとに変わったファイルがあれば `--force`）。
  - 新しいノートの置き場所は元と同じフォルダだけ（本文中の相対リンクを書き換えずに済ませるため）。既存のファイルは上書きしない。

CLI（1 行の JSON）:
  split_notes.py split ROOT SRC '見出し' NEWFILE
  split_notes.py undo ROOT [--force]
  split_notes.py last ROOT
"""
from __future__ import annotations

import datetime as dt
import hashlib
import json
import os
import re
import shutil
import sys
from pathlib import Path
from urllib.parse import quote, unquote

sys.path.insert(0, str(Path(__file__).resolve().parent))
from note_title import title_of_lines  # noqa: E402

HEAD = re.compile(r"^(#{1,6})\s+(.*?)\s*#*\s*$")
REL_HEADS = ("ParentBranch:", "ChildBranch:", "BranchGroup:", "Group:", "Context:", "Related:", "BackLink:")


def _sha(p: Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()


def _body_start(lines: list[str]) -> int:
    if lines and lines[0].strip() == "---":
        for i in range(1, len(lines)):
            if lines[i].strip() == "---":
                return i + 1
    return 0


def _headings(lines: list[str], start: int) -> list[tuple[int, int, str]]:
    out, fence = [], False
    for i in range(start, len(lines)):
        t = lines[i]
        if t.lstrip().startswith(("```", "~~~")):
            fence = not fence
            continue
        m = None if fence else HEAD.match(t)
        if m:
            out.append((i, len(m.group(1)), m.group(2)))
    return out


def _section(lines: list[str], heading: str) -> tuple[int, int, int, str]:
    start = _body_start(lines)
    hs = _headings(lines, start)
    found = [h for h in hs if h[2] == heading]
    if not found:
        raise ValueError("その見出しがありません: " + heading)
    if len(found) > 1:
        raise ValueError("同じ見出しが複数あります（どれか分かりません）: " + heading)
    i, level, _ = found[0]
    if level == 1 and i == min(h[0] for h in hs):
        raise ValueError("ノートの題（最初の H1）は分割できません")
    end = len(lines)
    for j, lv, _ in hs:
        if j > i and lv <= level:
            end = j
            break
    for j in range(i + 1, end):                               # 末尾の関係ブロックは含めない
        if lines[j].strip() in REL_HEADS and lines[j] == lines[j].lstrip():
            end = j
            break
    return i, end, level, found[0][2]


def _backup(root: Path, stamp: str, files: list[Path], created: list[Path]) -> Path:
    d = root / ".state" / "split-undo" / stamp
    d.mkdir(parents=True, exist_ok=True)
    meta = {"files": [], "created": []}
    for f in files:
        rel = f.relative_to(root).as_posix()
        (d / "files" / Path(rel).parent).mkdir(parents=True, exist_ok=True)
        shutil.copy2(f, d / "files" / rel)
        meta["files"].append(rel)
    meta["created"] = [c.relative_to(root).as_posix() for c in created]
    (d / "meta.json").write_text(json.dumps(meta, ensure_ascii=False), encoding="utf-8")
    return d


def _write(p: Path, text: str) -> None:
    tmp = p.with_name(p.name + ".tmp")
    tmp.write_text(text, encoding="utf-8")
    os.replace(tmp, p)


def split(root: str | Path, src: str, heading: str, newfile: str, now: dt.datetime | None = None) -> dict:
    root = Path(root).resolve()
    sp = (root / src).resolve()
    np_ = (root / newfile).resolve()
    for p in (sp, np_):
        try:
            rel = p.relative_to(root)
        except ValueError:
            raise ValueError("vault の外は扱いません") from None
        if any(part.startswith(".") for part in rel.parts):
            raise ValueError("ドット始まりのフォルダは扱いません")
    if not sp.is_file():
        raise ValueError("元のノートがありません: " + src)
    if np_.suffix != ".md" or np_.parent != sp.parent:
        raise ValueError("新しいノートは、元と同じフォルダの .md にしてください")
    if np_.exists():
        raise ValueError("すでにあります（上書きしません）: " + np_.name)
    now = now or dt.datetime.now()
    text = sp.read_text(encoding="utf-8")
    lines = text.split("\n")
    i, end, level, title = _section(lines, heading)
    body = lines[i + 1:end]
    while body and not body[0].strip():
        body.pop(0)
    while body and not body[-1].strip():
        body.pop()
    if not body:
        raise ValueError("その節は中身が空なので分割しません")
    src_title = title_of_lines(lines, sp.stem)
    link_new = quote(np_.name)
    new_text = (f"---\ntime: {now:%Y-%m-%d %H:%M:%S}\ntitle: {title}\n---\n\n# {title}\n\n" + "\n".join(body) +
                f"\n\nRelated:\n[{src_title}]({quote(sp.name)})\n")
    stub = [lines[i], "", f"→ [{title}]({link_new})（分割しました）", ""]
    new_src = lines[:i] + stub + lines[end:]
    # 元ノート#見出し を指す他ノートのリンクを、新しいノートへ
    rewrites: dict[Path, str] = {}
    anchors = {title, quote(title), title.replace(" ", "-").lower()}
    pat = re.compile(r"\]\(([^)#\s]+)#([^)\s]+)\)")
    for p in root.rglob("*.md"):
        if any(part.startswith(".") for part in p.relative_to(root).parts) or p == np_:
            continue
        t = (p.read_text(encoding="utf-8") if p != sp else "\n".join(new_src))
        def sub(m):
            tgt = (p.parent / unquote(m.group(1))).resolve()
            if tgt == sp and (m.group(2) in anchors or unquote(m.group(2)) in anchors):
                rel = os.path.relpath(np_, p.parent).replace(os.sep, "/")
                return f"]({quote(rel)})"
            return m.group(0)
        nt = pat.sub(sub, t)
        if p == sp:
            new_src = nt.split("\n")
        elif nt != t:
            rewrites[p] = nt
    stamp = now.strftime("%Y%m%d-%H%M%S")
    touched = [sp] + list(rewrites)
    undo_dir = _backup(root, stamp, touched, [np_])
    _write(np_, new_text)
    _write(sp, "\n".join(new_src))
    for p, t in rewrites.items():
        _write(p, t)
    meta = json.loads((undo_dir / "meta.json").read_text(encoding="utf-8"))
    meta["after"] = {r: _sha(root / r) for r in meta["files"] + meta["created"]}
    (undo_dir / "meta.json").write_text(json.dumps(meta, ensure_ascii=False), encoding="utf-8")
    return {"ok": True, "src": sp.relative_to(root).as_posix(), "new": np_.relative_to(root).as_posix(), "heading": title, "lines": len(body),
            "relinked": sorted(p.relative_to(root).as_posix() for p in rewrites), "undo": stamp}


def _last(root: Path):
    base = root / ".state" / "split-undo"
    ds = sorted(d for d in base.iterdir() if not d.name.endswith(".done") and (d / "meta.json").is_file()) if base.is_dir() else []   # 取り消し済み(.done)は対象外
    return ds[-1] if ds else None


def last(root: str | Path) -> dict:
    d = _last(Path(root).resolve())
    if not d:
        return {"ok": False}
    meta = json.loads((d / "meta.json").read_text(encoding="utf-8"))
    return {"ok": True, "undo": d.name, "files": meta["files"], "created": meta["created"]}


def undo(root: str | Path, force: bool = False) -> dict:
    root = Path(root).resolve()
    d = _last(root)
    if not d:
        return {"ok": False, "error": "取り消せる分割がありません"}
    meta = json.loads((d / "meta.json").read_text(encoding="utf-8"))
    changed = [r for r, h in meta.get("after", {}).items() if not (root / r).is_file() or _sha(root / r) != h]
    if changed and not force:
        return {"ok": False, "error": "分割のあとに変わったファイルがあります（--force で元に戻す）", "changed": changed}
    for r in meta["files"]:
        shutil.copy2(d / "files" / r, root / r)
    for r in meta["created"]:
        (root / r).unlink(missing_ok=True)
    shutil.move(str(d), str(d.with_name(d.name + ".done")))        # 同じ分割を 2 回取り消さない
    return {"ok": True, "restored": meta["files"], "removed": meta["created"]}


def main(argv: list[str]) -> int:
    try:
        force = "--force" in argv
        a = [x for x in argv if x != "--force"]
        if len(a) == 5 and a[0] == "split":
            r = split(a[1], a[2], a[3], a[4])
        elif len(a) == 2 and a[0] == "undo":
            r = undo(a[1], force)
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
