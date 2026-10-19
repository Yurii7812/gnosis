#!/usr/bin/env python3
"""どこにもつながっていないノート（オーファン）の一覧。

他のノートへのリンクも、他のノートからのリンクも無いノートを探す。
Index・操作ガイド・日記は「つながり」に数えない（日記は作ったノートへ自動でリンクするため）。

CLI: orphans.py ROOT   → 1 行 1 件 `絶対パス<TAB>タイトル<TAB>トピック`（新しい順。トピックはスマホのメモの capture:）
"""
from __future__ import annotations

import os
import re
import sys
from pathlib import Path
from urllib.parse import unquote

try:
    import note_format_v2 as nf
except ImportError:
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import note_format_v2 as nf

_DIARY_RE = re.compile(r"^\d{4}-\d{2}-\d{2}(-.+)?\.md$")
_SKIP_NAMES = {"index.md", "gnosis-guide.md", "simple-yurii-note-guide.md"}


def _skipped(p: Path) -> bool:
    return p.name.lower() in _SKIP_NAMES or bool(_DIARY_RE.match(p.name))


def find_orphans(root) -> list[tuple[Path, str]]:
    root = Path(root).resolve()
    notes: dict[Path, str] = {}
    for p in nf._iter_md(root):
        try:
            notes[Path(os.path.normpath(str(p.resolve())))] = p.read_text(encoding="utf-8")
        except OSError:
            continue
    known = {str(p) for p in notes}
    linked: set[Path] = set()
    for p, text in notes.items():
        if _skipped(p):
            continue
        for tg in nf._links_in(text.split("\n")):
            for cand in (tg, unquote(tg)):
                q = Path(os.path.normpath(cand if cand.startswith("/") else os.path.join(str(p.parent), cand)))
                if str(q) in known and q != p and not _skipped(q):
                    linked.add(p)
                    linked.add(q)
                    break
    out = []
    for p, text in notes.items():
        if _skipped(p) or p in linked:
            continue
        out.append((p, nf._simple_parse_text(p, text)["title"], _topic(text)))
    out.sort(key=lambda x: x[0].stat().st_mtime, reverse=True)
    return out


def _topic(text: str) -> str:
    lines = text.split("\n")
    if not lines or lines[0].strip() != "---":
        return ""
    for ln in lines[1:30]:
        if ln.strip() == "---":
            break
        m = re.match(r"^capture:\s*(.+?)\s*$", ln)
        if m:
            return m.group(1)
    return ""


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print(__doc__, file=sys.stderr)
        return 2
    for p, title, topic in find_orphans(argv[1]):
        print(f"{p}\t{title}\t{topic}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
