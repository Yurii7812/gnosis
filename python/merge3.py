#!/usr/bin/env python3
"""3 者マージ（行単位）。同期が書き換えたファイル（theirs）と、手元の未保存の編集（ours）を、
最後に読んだ・書いた内容（base）から数えて、**別々の場所**の変更なら両方を取り込む。同じ場所なら失敗（None）。

    merge3.py BASE OURS THEIRS OUT     成功なら OUT に結果を書いて終了コード 0、衝突なら 1
"""
from __future__ import annotations

import difflib
import sys
from pathlib import Path


def _changes(base: list[str], other: list[str]) -> list[tuple[int, int, list[str]]]:
    sm = difflib.SequenceMatcher(None, base, other, autojunk=False)
    return [(i1, i2, other[j1:j2]) for tag, i1, i2, j1, j2 in sm.get_opcodes() if tag != "equal"]


def _overlap(a: tuple[int, int, list[str]], b: tuple[int, int, list[str]]) -> bool:
    (a1, a2, ar), (b1, b2, br) = a, b
    if a1 == a2 and b1 == b2:            # 同じ位置への挿入どうし（同じ内容なら重ならない扱い）
        return a1 == b1 and ar != br
    if a1 == a2:                          # a は挿入: b の範囲の内側（端は除く）なら重なる
        return b1 < a1 < b2
    if b1 == b2:
        return a1 < b1 < a2
    return a1 < b2 and b1 < a2            # 範囲どうし


def merge3(base: list[str], ours: list[str], theirs: list[str]) -> list[str] | None:
    if ours == base:
        return list(theirs)
    if theirs == base or ours == theirs:
        return list(ours)
    co, ct = _changes(base, ours), _changes(base, theirs)
    for a in co:
        for b in ct:
            if _overlap(a, b):
                return None
    # 同じ位置への同一内容の挿入は 1 つだけ入れる
    allc = sorted(co + [c for c in ct if c not in co], key=lambda c: (c[0], c[1]))
    out: list[str] = []
    pos = 0
    for i1, i2, new in allc:
        out += base[pos:i1]
        out += new
        pos = max(pos, i2)
    out += base[pos:]
    return out


def main(argv: list[str]) -> int:
    if len(argv) != 4:
        print(__doc__, file=sys.stderr)
        return 2
    base, ours, theirs = (Path(p).read_text(encoding="utf-8").split("\n") for p in argv[:3])
    merged = merge3(base, ours, theirs)
    if merged is None:
        return 1
    Path(argv[3]).write_text("\n".join(merged), encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
