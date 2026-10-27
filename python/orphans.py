#!/usr/bin/env python3
"""未所属のノート（Folgezettel ID が無く、なおかつ親（Branch）も無いノート）の一覧。

Folgezettel ID（front matter の folgezettel:）があるノートは、Index・日記・時系列記録から Branch でたどれる
ので「所属あり」。ID が無くても、`ParentBranch:`（または相手の `ChildBranch:`）で親があるノートは、親をたどれるので
未所属ではない（番号の無いノートを親にしている子を出さないため）。ID が無く、親も無いものだけが未所属（\\a・\\N に出る）。
`BackLink:`・`Context:`・`Related:` だけでは「所属あり」にならない（Folgezettel は親子で数える）。
ID はまだ振られていなくても、次の同期で振られるもの（folgezettel.allocation の計画）は数えない。
番号が外されるもの（Index にも日記にも載らず親も無い）は、外した後の状態で数える。
Index・操作ガイド・グループ・日記・時系列記録・紙の PKM のノート（題が ID・folgezettel-Index など）は出さない。

CLI: orphans.py ROOT   → 1 行 1 件 `絶対パス<TAB>タイトル<TAB>トピック`（新しい順。topic:（旧 capture: も読む）。作成端末を区別しない）
"""
from __future__ import annotations

import json
import os
import re
import sys
from pathlib import Path
from urllib.parse import unquote

try:
    import note_format_v2 as nf
    import folgezettel as fz
except ImportError:
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import note_format_v2 as nf
    import folgezettel as fz

_SKIP_NAMES = {"index.md", "gnosis-guide.md", "simple-yurii-note-guide.md"}
# 紙の PKM のノート: スキャン（題が ID）・トピック（ID-題）・番号の一覧・紙の日記
_PAPER_RE = re.compile(r"^(?:\d+[a-z0-9]*(?:-.*)?|[Ff]olgezettel-Index(?:-.*)?|Paper-Zettelkasten-Index|\d{4}-\d{2}-\d{2}\(.*)$")


def find_orphans(root) -> list[tuple[Path, str, str]]:
    root = Path(root).resolve()
    notes: dict[Path, dict] = {}
    texts: dict[Path, str] = {}
    for p in nf._iter_md(root):
        try:
            text = p.read_text(encoding="utf-8")
        except OSError:
            continue
        rp = p.resolve()
        texts[rp] = text
        notes[rp] = nf._simple_parse_text(rp, text)
    planned = fz.allocation(root, notes)
    # 親（Branch）があるノート: 自分の ParentBranch: の宛先、または相手の ChildBranch: に自分が書かれているもの
    has_parent: set[Path] = set()

    def targets(lines, base):
        for _, link in nf._links_from(lines):
            raw = link.split("#", 1)[0]
            for cand in (raw, unquote(raw)):
                q = (base / cand).resolve()
                if q in notes:
                    yield q
                    break

    for p, n in notes.items():
        if any(q != p for q in targets(n["pbranch"], p.parent)):
            has_parent.add(p)
        for q in targets(n["cbranch"], p.parent):
            if q != p:
                has_parent.add(q)
    out = []
    for p, n in notes.items():
        if p.name.lower() in _SKIP_NAMES or fz.is_group(n) or fz.is_daily(n) or _PAPER_RE.match(n["title"]):
            continue
        if (planned[p] if p in planned else fz.value(texts[p])) or p in has_parent:
            continue
        out.append((p, n["title"], _topic(texts[p])))
    out.sort(key=lambda x: x[0].stat().st_mtime, reverse=True)
    return out


def _topic(text: str) -> str:
    lines = text.split("\n")
    if not lines or lines[0].strip() != "---":
        return ""
    legacy = ""
    for ln in lines[1:]:
        if ln.strip() == "---":
            break
        m = re.match(r"^topic:\s*(.*?)\s*$", ln)
        if m:
            value = m.group(1)
            try:
                return str(json.loads(value)) if value.startswith('"') else value.strip("'")
            except ValueError:
                return value
        m = re.match(r"^capture:\s*(.*?)\s*$", ln)
        if m:
            legacy = m.group(1).strip("\"'")
    return "" if legacy == "メモ" else legacy


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print(__doc__, file=sys.stderr)
        return 2
    for p, title, topic in find_orphans(argv[1]):
        print(f"{p}\t{title}\t{topic}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
