#!/usr/bin/env python3
"""ノートのマージ（\\l → m）と、その取り消し。

スマホのメモなど、小さなノート（SRC）の中身を別のノート（DST）にまとめる。

  - DST の本文の最後（ChildBranch: などの節の手前）に、SRC の本文（H1 と上のブロックを除く）を空行 1 つ空けて足す。
  - SRC の Context: / BranchGroup: / Related: のリンクは DST にも足す（同じ相手は 1 本）。SRC の親（ParentBranch:）は、
    DST に親が無いときだけ DST の親にする。
  - vault の中で SRC を指していたリンクは、すべて DST を指すように書き換える（表示名が SRC の題なら DST の題に）。
    同じブロックに同じ相手が 2 本になったら 1 本にする。DST の中の SRC へのリンクは消す（自分へのリンクになるので）。
    DST にもう親があるときは、SRC の親の ChildBranch: から DST を外す（親は 1 つ）。
  - スマホのメモの取り込み記録（.state/capture_imported.json）で SRC を指していたものも DST を指すようにする
    （スマホ側で「取り込み済み」のまま、二度取り込まないように）。
  - SRC のファイルは消す。変えるファイルは変える前に .state/merge-undo/<日時>/ に控え、`undo` で全部元に戻せる。

Vim で未保存の編集があるノートが関わるときは何もしない。

CLI（結果は 1 行の JSON）:
    merge_notes.py merge ROOT SRC DST
    merge_notes.py undo ROOT [--force]      # 直前のマージを取り消す（マージのあとに変わったファイルがあれば --force が要る）
    merge_notes.py last ROOT                # 取り消せるマージ（無ければ {"ok": false}）
"""
from __future__ import annotations

import json
import re
import shutil
import sys
import time
from pathlib import Path
from urllib.parse import unquote

try:
    import note_format_v2 as nf
    import context_ops
    import branch_ops
except ImportError:
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import note_format_v2 as nf
    import context_ops
    import branch_ops

UNDO_DIR = ".state/merge-undo"
CAPTURE_STATE = ".state/capture_imported.json"
LINK_RE = re.compile(r"\[((?:\\.|[^\]\\])*)\]\(([^)\s]+)\)")
# 本文の下の節（ここから上が本文）
_LOWER_HEADS = {nf.CHILD_BRANCH_MARK, nf.CHILD_BRANCH_MARK_LEGACY, nf.RELATED_MARK, nf.RELATED_MARK_LEGACY,
                nf.BACKLINK_MARK, nf.BACKLINK_MARK_LEGACY, nf.CONTEXT_MARK, nf.UP_MARK, nf.LEGACY_GROUP_MARK,
                nf.PARENT_BRANCH_MARK_LEGACY}
_TOP_HEADS = {nf.PARENT_BRANCH_MARK, nf.BRANCH_GROUP_HEAD, nf.LEGACY_THIS_NOTE_GROUP_HEAD, nf.GROUP_MARK,
              nf.CONTEXT_HEAD}


def _resolve(target: str, base: Path) -> Path | None:
    raw = target.split("#", 1)[0]
    if not raw or "://" in raw or not raw.endswith(".md"):
        return None
    for cand in (raw, unquote(raw)):
        p = (base / cand).resolve()
        if p.exists():
            return p
    return (base / unquote(raw)).resolve()


def _is_group(text: str) -> bool:
    fm, _ = nf._split_front_matter(text.split("\n"))
    return bool(nf._GROUP_ATTR_RE.search("\n".join(fm)))


def _title(path: Path, text: str) -> str:
    fm, _ = nf._split_front_matter(text.split("\n"))
    return nf._fm_title(fm) or path.stem


def _block_links(lines: list[str], head: str) -> list[str]:
    """先頭のブロック head（Context: など）の直下のリンク行。"""
    flags = nf._fenced(lines)
    for i, ln in enumerate(lines):
        if not flags[i] and ln.strip() == head:
            out = []
            j = i + 1
            while j < len(lines) and nf._SIMPLE_LINK_LINE_RE.match(lines[j]):
                out.append(lines[j].strip())
                j += 1
            return out
    return []


def _section_links(lines: list[str], heads: set[str]) -> list[str]:
    flags = nf._fenced(lines)
    out, on = [], False
    for i, ln in enumerate(lines):
        if flags[i]:
            continue
        s = ln.strip()
        if s in _LOWER_HEADS or s in _TOP_HEADS:
            on = s in heads
            continue
        if on and nf._SIMPLE_LINK_LINE_RE.match(ln):
            out.append(s)
    return out


def _src_body(lines: list[str]) -> list[str]:
    """SRC の本文（H1・front matter・上のブロック・下の節を除く）。"""
    fm, rest = nf._split_front_matter(lines)
    flags = nf._fenced(rest)
    out: list[str] = []
    i = 0
    seen_h1 = False
    # H1 と上のブロックを飛ばす
    while i < len(rest):
        s = rest[i].strip()
        if flags[i]:
            break
        if not seen_h1 and re.match(r"^#\s+\S", rest[i]):
            seen_h1 = True
            i += 1
            continue
        if s == "":
            i += 1
            continue
        if s in _TOP_HEADS:
            i += 1
            while i < len(rest) and nf._SIMPLE_LINK_LINE_RE.match(rest[i]):
                i += 1
            continue
        break
    while i < len(rest):
        if not flags[i] and rest[i].strip() in _LOWER_HEADS:
            break
        out.append(rest[i])
        i += 1
    while out and not out[0].strip():
        out.pop(0)
    while out and not out[-1].strip():
        out.pop()
    return out


def _body_end(lines: list[str]) -> int:
    """本文の終わり（最初の下の節の見出しの行。無ければ末尾）。"""
    fm, _ = nf._split_front_matter(lines)
    flags = nf._fenced(lines)
    for i in range(len(fm), len(lines)):
        if not flags[i] and lines[i].strip() in _LOWER_HEADS:
            return i
    return len(lines)


def _rewrite_links(lines: list[str], base: Path, src: Path, dst: Path, src_title: str, dst_title: str,
                   self_path: Path) -> list[str]:
    """SRC へのリンクを DST へ。self_path が DST なら、SRC へのリンク（自分へのリンクになる）は消す。"""
    out: list[str] = []
    flags = nf._fenced(lines)
    for i, ln in enumerate(lines):
        if flags[i] or "](" not in ln:
            out.append(ln)
            continue
        only = nf._SIMPLE_LINK_LINE_RE.match(ln)
        drop = False

        def sub(m):
            nonlocal drop
            text, target = m.group(1), m.group(2)
            if _resolve(target, base) != src:
                return m.group(0)
            if self_path == dst:
                drop = bool(only)
                return text
            anchor = target.split("#", 1)[1] if "#" in target else ""
            new = nf._rel(base, dst) + ("#" + anchor if anchor else "")
            if text == src_title:
                text = dst_title
            return f"[{text}]({new})"

        new = LINK_RE.sub(sub, ln)
        if drop:
            continue
        out.append(new)
    return _dedupe_link_runs(out, base)


def _dedupe_link_runs(lines: list[str], base: Path) -> list[str]:
    """続いているリンク行の中で、同じ相手へのリンクを 1 本にする。"""
    out: list[str] = []
    run: set = set()
    flags = nf._fenced(lines)
    for i, ln in enumerate(lines):
        m = None if flags[i] else nf._SIMPLE_LINK_LINE_RE.match(ln)
        if not m:
            run = set()
            out.append(ln)
            continue
        t = LINK_RE.search(ln)
        key = _resolve(t.group(2), base) if t else None
        if key is not None and key in run:
            continue
        if key is not None:
            run.add(key)
        out.append(ln)
    return out


def _remove_child_line(lines: list[str], base: Path, child: Path) -> list[str]:
    """ChildBranch: の節から child へのリンク行を外す。"""
    out, on = [], False
    flags = nf._fenced(lines)
    for i, ln in enumerate(lines):
        s = ln.strip()
        if not flags[i] and (s in _LOWER_HEADS or s in _TOP_HEADS):
            on = s in (nf.CHILD_BRANCH_MARK, nf.CHILD_BRANCH_MARK_LEGACY)
        elif on and nf._SIMPLE_LINK_LINE_RE.match(ln):
            t = LINK_RE.search(ln)
            if t and _resolve(t.group(2), base) == child:
                continue
        out.append(ln)
    return out


def _result(ok: bool, **kw) -> dict:
    return {"ok": ok, **kw}


def merge(root, src, dst) -> dict:
    root = Path(root).resolve()
    src, dst = Path(src).resolve(), Path(dst).resolve()
    if src == dst:
        return _result(False, code="same", message="同じノートはマージできません")
    for p in (src, dst):
        if not p.is_file():
            return _result(False, code="missing", message=f"ノートがありません: {p.name}")
        if p.name == "index.md":
            return _result(False, code="index", message="Index はマージできません")
    src_text = src.read_text(encoding="utf-8")
    dst_text = dst.read_text(encoding="utf-8")
    if _is_group(src_text):
        return _result(False, code="group", message="グループはマージの元にできません")
    src_title, dst_title = _title(src, src_text), _title(dst, dst_text)

    # 変えるファイルを先に集める（SRC を指すリンクがあるノート）
    texts: dict[Path, str] = {}
    for p in nf._iter_md(root):
        rp = p.resolve()
        if rp == src:
            continue
        t = dst_text if rp == dst else p.read_text(encoding="utf-8")
        if rp == dst or any(_resolve(m.group(2), rp.parent) == src for m in LINK_RE.finditer(t)):
            texts[rp] = t
    busy = [p.name for p in list(texts) + [src] if nf._editor_has_unsaved_changes(p)]
    if busy:
        return _result(False, code="unsaved", message="未保存の編集があるノートがあります: " + ", ".join(busy))

    # DST の新しい中身
    src_lines = src_text.rstrip("\n").split("\n")
    lines = dst_text.rstrip("\n").split("\n")
    body = _src_body(src_lines)
    if body:
        at = _body_end(lines)
        k = at
        while k > 0 and not lines[k - 1].strip():
            k -= 1
        tail = [""] if at < len(lines) else []
        lines[k:at] = [""] + body + tail
    for link in _block_links(src_lines, nf.CONTEXT_HEAD) + _section_links(src_lines, {nf.CONTEXT_MARK, nf.UP_MARK}):
        t = LINK_RE.search(link)
        if t and _resolve(t.group(2), src.parent) not in (dst, src):
            lines, _ = context_ops.add_link(lines, link, dst.parent)
    have_bg = {_resolve(LINK_RE.search(l).group(2), dst.parent) for l in _block_links(lines, nf.BRANCH_GROUP_HEAD)}
    for link in _block_links(src_lines, nf.BRANCH_GROUP_HEAD) + _block_links(src_lines, nf.LEGACY_THIS_NOTE_GROUP_HEAD):
        if _resolve(LINK_RE.search(link).group(2), src.parent) not in have_bg:
            lines = branch_ops._insert_top_block_link(lines, nf.BRANCH_GROUP_HEAD, link).split("\n")
    text = "\n".join(lines) + "\n"
    have_rel = {_resolve(LINK_RE.search(l).group(2), dst.parent) for l in _section_links(lines, {nf.RELATED_MARK, nf.RELATED_MARK_LEGACY})}
    for link in _section_links(src_lines, {nf.RELATED_MARK, nf.RELATED_MARK_LEGACY}):
        q = _resolve(LINK_RE.search(link).group(2), src.parent)
        if q not in have_rel and q != dst:
            text = branch_ops.insert_link(text, nf.RELATED_MARK, link)
    dst_parents = _block_links(text.split("\n"), nf.PARENT_BRANCH_MARK)
    src_parents = _block_links(src_lines, nf.PARENT_BRANCH_MARK)
    src_parent_paths = [p for p in (_resolve(LINK_RE.search(l).group(2), src.parent) for l in src_parents) if p]
    if not dst_parents and src_parents and src_parent_paths and src_parent_paths[0] != dst:
        text = branch_ops._insert_top_block_link(text.rstrip("\n").split("\n"), nf.PARENT_BRANCH_MARK, src_parents[0]) + "\n"
        dst_has_parent_from_src = True
    else:
        dst_has_parent_from_src = False
    texts[dst] = text

    # ほかのノートのリンクを書き換える
    new_texts: dict[Path, str] = {}
    for p, t in texts.items():
        ls = t.rstrip("\n").split("\n") if p != dst else t.rstrip("\n").split("\n")
        ls = _rewrite_links(ls, p.parent, src, dst, src_title, dst_title, p)
        if p in src_parent_paths and dst_parents and not dst_has_parent_from_src:
            # DST にはもう親がある: SRC の親の ChildBranch: には DST を書かない（親は 1 つ）
            ls = _remove_child_line(ls, p.parent, dst)
        new_texts[p] = "\n".join(ls) + "\n"

    # 取り込み記録
    state_path = root / CAPTURE_STATE
    state_new = None
    if state_path.is_file():
        st = json.loads(state_path.read_text(encoding="utf-8"))
        rel_src, rel_dst = nf._rel(root, src), nf._rel(root, dst)
        changed = False
        for k, v in list(st.get("ids", {}).items()):
            base = v.split("#", 1)[0]
            if base == rel_src:
                st["ids"][k] = rel_dst
                changed = True
        if changed:
            state_new = json.dumps(st, ensure_ascii=False, indent=1)

    # 控えを取ってから書く
    stamp = time.strftime("%Y%m%d-%H%M%S")
    bdir = root / UNDO_DIR / stamp
    n = 2
    while bdir.exists():
        bdir = root / UNDO_DIR / f"{stamp}-{n}"
        n += 1
    (bdir / "files").mkdir(parents=True)
    saved = [src] + list(new_texts) + ([state_path] if state_new is not None else [])
    for p in saved:
        rel = p.relative_to(root)
        (bdir / "files" / rel).parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(p, bdir / "files" / rel)
    for p, t in new_texts.items():
        if t != texts.get(p) or p == dst:
            p.write_text(t, encoding="utf-8")
    if state_new is not None:
        state_path.write_text(state_new, encoding="utf-8")
    src.unlink()
    # 同期してから「マージ直後の中身」を控える（取り消すときに、あとで変わったノートを見分けるため）
    nf.simple_sync(root)
    after = {str(p.relative_to(root)): nf._content_hash(p.read_text(encoding="utf-8"))
             for p in list(new_texts) + ([state_path] if state_new is not None else [])}
    manifest = {"version": 1, "src": str(src.relative_to(root)), "dst": str(dst.relative_to(root)),
                "src_title": src_title, "dst_title": dst_title, "files": [str(p.relative_to(root)) for p in saved],
                "after": after, "time": stamp}
    (bdir / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=1), encoding="utf-8")
    return _result(True, src=str(src), dst=str(dst), changed=sorted(str(p) for p in new_texts), undo=bdir.name,
                   src_title=src_title, dst_title=dst_title)


def _last(root: Path) -> Path | None:
    d = root / UNDO_DIR
    if not d.is_dir():
        return None
    cands = sorted([p for p in d.iterdir() if (p / "manifest.json").is_file() and not (p / "undone").exists()],
                   key=lambda p: p.name)
    return cands[-1] if cands else None


def last(root) -> dict:
    root = Path(root).resolve()
    b = _last(root)
    if b is None:
        return _result(False, code="none", message="取り消せるマージはありません")
    m = json.loads((b / "manifest.json").read_text(encoding="utf-8"))
    return _result(True, **m, dir=b.name)


def undo(root, force: bool = False) -> dict:
    root = Path(root).resolve()
    b = _last(root)
    if b is None:
        return _result(False, code="none", message="取り消せるマージはありません")
    m = json.loads((b / "manifest.json").read_text(encoding="utf-8"))
    changed = []
    for rel, h in m.get("after", {}).items():
        p = root / rel
        if not p.is_file() or nf._content_hash(p.read_text(encoding="utf-8")) != h:
            changed.append(rel)
    if (root / m["src"]).exists():
        changed.append(m["src"])
    if changed and not force:
        return _result(False, code="changed", message="マージのあとに変わったノートがあります", files=changed)
    busy = [rel for rel in m["files"] if (root / rel).exists() and nf._editor_has_unsaved_changes(root / rel)]
    if busy:
        return _result(False, code="unsaved", message="未保存の編集があるノートがあります: " + ", ".join(busy))
    for rel in m["files"]:
        dest = root / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(b / "files" / rel, dest)
    (b / "undone").write_text(time.strftime("%Y-%m-%d %H:%M:%S") + "\n", encoding="utf-8")
    return _result(True, src=str(root / m["src"]), dst=str(root / m["dst"]), restored=m["files"], src_title=m.get("src_title", ""))


def main(argv: list[str]) -> int:
    if len(argv) == 5 and argv[1] == "merge":
        r = merge(argv[2], argv[3], argv[4])
    elif len(argv) >= 3 and argv[1] == "undo":
        r = undo(argv[2], force="--force" in argv[3:])
    elif len(argv) == 3 and argv[1] == "last":
        r = last(argv[2])
    else:
        print(__doc__, file=sys.stderr)
        return 2
    print(json.dumps(r, ensure_ascii=False))
    return 0 if r.get("ok") else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
