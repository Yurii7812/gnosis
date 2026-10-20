#!/usr/bin/env python3
"""日記と時系列記録の木（2026-10-20 決定）。

    時系列記録            … 普通のノート（Index の本文に載る）。本文に「日記」「夢」などのリンク
      日記               … 普通のノート。ParentBranch: 時系列記録。本文に年（無ければ月）のリンク
        2026             … 年。ParentBranch: 日記。本文に月のリンク
          2026-10        … 月。ParentBranch: 年（年が無ければ 日記）。本文にその日のノートのリンク
            2026-10-19-MO-… … その日のノート。ParentBranch: 月
      夢                 … 時系列記録の 1 つ。日記と同じ形（2026-夢 / 2026-10-夢 / 2026-10-19-MO-夢）

木の中のノート（その日のノートを除く）は front matter に `timeline: true` を持つ。グループではないので
Folgezettel ID が付き、ParentBranch をたどって番号が決まる（年ができて月の親が変われば、同期が番号を振り直す）。

使い方::

    diary_tree.py migrate ROOT [--dry-run]   # グループで作っていた古い木を、この形に直す
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from urllib.parse import unquote

sys.path.insert(0, str(Path(__file__).resolve().parent))
import note_format_v2 as nf  # noqa: E402
import branch_ops as bo  # noqa: E402

TIMELINE_RE = re.compile(r"^timeline\s*:\s*true\s*$", re.I)
_LINK_LINE_RE = re.compile(r"^\s*\[(?:\\.|[^\]\\])*\]\(([^)]+)\)\s*$")
_GROUP_ATTR_LINE_RE = re.compile(r"^attribute\s*:\s*(?:group|グループ)\s*$", re.I)
YEAR_RE = re.compile(r"^\d{4}$")
MONTH_RE = re.compile(r"^\d{4}-\d{2}$")
DAY_RE = re.compile(r"^\d{4}-\d{2}-\d{2}-[A-Z]{2}(?:-|$)")


def _split(text: str) -> tuple[list[str], bool]:
    lines = text.split("\n")
    nl = text.endswith("\n")
    if nl:
        lines.pop()
    return lines, nl


def _join(lines: list[str], nl: bool) -> str:
    return "\n".join(lines) + ("\n" if nl else "")


def make_container(text: str) -> str:
    """グループの印（attribute: group）を外し、木の印（timeline: true）を付ける。"""
    lines, nl = _split(text)
    fm, _ = nf._split_front_matter(lines)
    if not fm:
        return text
    body_fm = [ln for ln in fm[1:-1] if not _GROUP_ATTR_LINE_RE.match(ln.strip())]
    if not any(TIMELINE_RE.match(ln.strip()) for ln in body_fm):
        body_fm.append("timeline: true")
    return _join([fm[0]] + body_fm + [fm[-1]] + lines[len(fm):], nl)


def _block_ranges(lines: list[str], head: str) -> list[tuple[int, int]]:
    """本文の上の先頭のブロック `head`（Group: など）の (見出しの行, 最後のリンクの行 + 1)。"""
    out = []
    flags = nf._fenced(lines)
    i = 0
    while i < len(lines):
        if not flags[i] and lines[i].strip() == head:
            j = i + 1
            while j < len(lines) and _LINK_LINE_RE.match(lines[j]):
                j += 1
            out.append((i, j))
            i = j
        else:
            i += 1
    return out


def _target_name(line: str) -> str:
    m = _LINK_LINE_RE.match(line)
    if not m:
        return ""
    return Path(unquote(m.group(1).split("#", 1)[0])).name


def remove_block_links(text: str, head: str, names: set[str]) -> str:
    """ブロック `head` の中の、names（ファイル名）へのリンク行を外す。空になったら見出しも外す。"""
    lines, nl = _split(text)
    for start, end in reversed(_block_ranges(lines, head)):
        keep = [ln for ln in lines[start + 1:end] if _target_name(ln) not in names]
        if keep:
            lines[start + 1:end] = keep
        else:
            del lines[start:end]
            # 見出しの前後に空行が 2 つ並んだら 1 つにする
            if 0 < start < len(lines) and not lines[start].strip() and not lines[start - 1].strip():
                del lines[start]
    return _join(lines, nl)


def set_parent(text: str, link_line: str) -> str:
    """ParentBranch: を link_line の 1 本にする（親は 1 つだけ）。"""
    lines, nl = _split(text)
    for start, end in _block_ranges(lines, nf.PARENT_BRANCH_MARK):
        if end - start == 2 and lines[start + 1] == link_line:
            return text
    for start, end in reversed(_block_ranges(lines, nf.PARENT_BRANCH_MARK)):
        del lines[start:end]
    return bo._insert_top_block_link(lines, nf.PARENT_BRANCH_MARK, link_line) + ("\n" if nl else "")


def _title(text: str, path: Path) -> str:
    return bo.note_title(text, path)


def _is_group(text: str) -> bool:
    fm, _ = nf._split_front_matter(text.split("\n"))
    return any(_GROUP_ATTR_LINE_RE.match(ln.strip()) for ln in fm)


def _body_links(text: str, path: Path, known: dict[str, Path]) -> list[Path]:
    """本文（上のブロックと下の節を除く）にリンク行があるノート。"""
    lines, _ = _split(text)
    fm, _rest = nf._split_front_matter(lines)
    flags = nf._fenced(lines)
    out: list[Path] = []
    in_top = False
    for i in range(len(fm), len(lines)):
        if flags[i]:
            continue
        s = lines[i].strip()
        if s in bo._TOP_BLOCK_HEADS:
            in_top = True
            continue
        if in_top and _LINK_LINE_RE.match(lines[i]):
            continue
        in_top = False
        if s in nf.ALL_SECTION_HEADS or s in ("ChildBranch:", "Related:", "BackLink:"):
            break
        name = _target_name(lines[i])
        if name and name in known and known[name] not in out:
            out.append(known[name])
    return out


def migrate(root, dry_run: bool = False) -> dict:
    root = Path(root).resolve()
    known = {p.name: p.resolve() for p in nf._iter_md(root)}
    texts = {p: p.read_text(encoding="utf-8") for p in known.values()}
    titles = {p: _title(t, p) for p, t in texts.items()}
    rec = next((p for p, t in titles.items() if t == "時系列記録"), None)
    if rec is None:
        return {"ok": True, "changed": [], "message": "時系列記録がありません"}
    plan: dict[Path, str] = {}

    def link(frm: Path, to: Path) -> str:
        return bo._link(frm.parent, to, titles[to])

    def container(p: Path, parent: Path | None) -> None:
        t = plan.get(p, texts[p])
        t = make_container(t)
        if parent is not None:
            # グループだったときの所属（Group: の親）は外し、ParentBranch: にする
            t = remove_block_links(t, nf.GROUP_MARK, {parent.name})
            t = set_parent(t, link(p, parent))
        plan[p] = t

    def day(p: Path, parent: Path) -> None:
        t = plan.get(p, texts[p])
        t = remove_block_links(t, nf.GROUP_MARK, {parent.name})
        t = set_parent(t, link(p, parent))
        plan[p] = t

    def walk(p: Path, parent: Path | None, depth: int) -> None:
        container(p, parent)
        for c in _body_links(texts[p], p, known):
            if c == p or c.name == "index.md":
                continue
            ct = titles[c]
            # 年・月（日記は 2026 / 2026-10、ほかの記録は 2026-夢 / 2026-10-夢）
            if YEAR_RE.match(ct[:4]) and (YEAR_RE.match(ct) or MONTH_RE.match(ct)
                                          or re.match(r"^\d{4}(?:-\d{2})?-", ct) and not DAY_RE.match(ct)):
                if _is_group(texts[c]) or TIMELINE_RE.search("\n".join(nf._split_front_matter(texts[c].split("\n"))[0])):
                    walk(c, p, depth + 1)
                    continue
            if DAY_RE.match(ct) and not _is_group(texts[c]):
                day(c, p)

    container(rec, None)
    for c in _body_links(texts[rec], rec, known):
        if c.name == "index.md" or c == rec:
            continue
        if _is_group(texts[c]) or TIMELINE_RE.search("\n".join(nf._split_front_matter(texts[c].split("\n"))[0])):
            walk(c, rec, 1)
    changed = [p for p, t in plan.items() if t != texts[p]]
    if not dry_run:
        for p in changed:
            p.write_text(plan[p], encoding="utf-8")
    return {"ok": True, "changed": [str(p) for p in changed]}


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(prog="diary_tree.py")
    sub = ap.add_subparsers(dest="mode", required=True)
    p_m = sub.add_parser("migrate")
    p_m.add_argument("root")
    p_m.add_argument("--dry-run", action="store_true")
    args = ap.parse_args(argv)
    if args.mode == "migrate":
        r = migrate(args.root, args.dry_run)
        print(json.dumps(r, ensure_ascii=False))
        return 0 if r["ok"] else 1
    return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
