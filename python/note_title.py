#!/usr/bin/env python3
"""ノートの題。2026-10-23〜 先頭の `# 見出し`（H1）が題。YAML の `title:` はもう書かない（古いノートに残っていれば、H1 が無いときだけ使う）。

  title_of_text(text, stem)  … H1（コードブロックの外・front matter の後ろの最初の `# `）→ YAML title: → stem
"""
from __future__ import annotations

import re

_H1 = re.compile(r"^#\s+(\S.*?)\s*#*\s*$")
_FENCE = re.compile(r"^\s{0,3}(`{3,}|~{3,})")
_YT = re.compile(r"^\s*title\s*:\s*(.+?)\s*$")


def title_of_lines(lines: list[str], stem: str = "") -> str:
    i = 0
    yaml_title = ""
    if lines and lines[0].strip() == "---":
        for j in range(1, len(lines)):
            if lines[j].strip() in ("---", "..."):
                i = j + 1
                break
            m = _YT.match(lines[j])
            if m and not yaml_title:
                yaml_title = m.group(1).strip().strip("\"'")
    fence = False
    for ln in lines[i:]:
        if _FENCE.match(ln):
            fence = not fence
            continue
        if not fence:
            m = _H1.match(ln)
            if m:
                return m.group(1).strip()
    return yaml_title or stem


def title_of_text(text: str, stem: str = "") -> str:
    return title_of_lines(text.split("\n"), stem)
