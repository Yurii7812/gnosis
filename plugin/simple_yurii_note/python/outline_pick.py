#!/usr/bin/env python3
"""zo / zn→t の見出しピッカー（fzf）用ヘルパー。

filter <tsv> <query>
    tsv の各行は `表示\tスラッグ\tパス\t行番号\t本文`。表示（見出し）だけを出す
    ので左の画面には見出ししか出ない。絞り込みはクエリの各語（空白・全角スペース
    区切り、すべて含む = AND、大文字小文字無視）を、見出しに含む行を先に、見出しには
    無く本文にだけ含む行をその後ろに並べる（それぞれファイル順）。
    クエリが空なら全件（スラッグ空の行 =「（見出しなし）」を先頭に）。
preview <path> <lnum> <query>
    lnum の見出しから 40 行を出し、クエリ語を ANSI で強調する。
"""
from __future__ import annotations

import re
import sys

RED = "\033[1;31m"
RESET = "\033[0m"


def tokens(query: str) -> list[str]:
    return [t.lower() for t in re.split(r"[\s　]+", query) if t]


def cmd_filter(tsv: str, query: str) -> int:
    toks = tokens(query)
    head_hits: list[str] = []
    body_hits: list[str] = []
    try:
        with open(tsv, encoding="utf-8") as f:
            rows = [r.rstrip("\n").split("\t") for r in f]
    except OSError:
        return 1
    for r in rows:
        r += [""] * (5 - len(r))
        disp, slug, path, lnum, body = r[:5]
        if not slug:  # 「（見出しなし）」
            if not toks:
                head_hits.append(disp)
            continue
        line = "\t".join([disp, slug, path, lnum])
        if all(t in disp.lower() for t in toks):
            head_hits.append(line)
        elif all(t in (disp + " " + body).lower() for t in toks):
            body_hits.append(line)
    sys.stdout.write("\n".join(head_hits + body_hits) + "\n")
    return 0


def highlight(line: str, toks: list[str]) -> str:
    for t in toks:
        out: list[str] = []
        idx = 0
        while True:
            j = line.lower().find(t, idx)
            if j < 0:
                out.append(line[idx:])
                break
            out.append(line[idx:j] + RED + line[j:j + len(t)] + RESET)
            idx = j + len(t)
        line = "".join(out)
    return line


def cmd_preview(path: str, lnum: str, query: str) -> int:
    toks = tokens(query)
    try:
        start = max(int(lnum) - 1, 0)
        with open(path, encoding="utf-8", errors="ignore") as f:
            lines = f.read().split("\n")
    except (OSError, ValueError):
        return 1
    sys.stdout.write("\n".join(highlight(ln, toks) for ln in lines[start:start + 40]))
    return 0


def main() -> int:
    a = sys.argv[1:]
    if len(a) >= 2 and a[0] == "filter":
        return cmd_filter(a[1], " ".join(a[2:]))
    if len(a) >= 3 and a[0] == "preview":
        return cmd_preview(a[1], a[2], " ".join(a[3:]))
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
