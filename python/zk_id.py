#!/usr/bin/env python3
"""区画とトピックの番号（1a から始める。2026-11-17 の決定）。

形: 先頭の数字が区画（`51`）、その後は「文字の段」「数字の段」が交互に続く（`51a1a`）。
- 並び: 段ごとに比べる。数字の段は数値（1a2 < 1a10）、文字の段は z の次が aa（26 → 27）。
- 続き: 最後が数字の段なら、その数字を 1 つ進める（1a1 → 1a2）。最後が文字の段なら 1 を足す（1a → 1a1）。
- 分岐: 最後が文字の段なら 1 を、数字の段なら a を足す（1a2 → 1a2a。1a → 1a1）。
- どちらも、できた番号がすでに使われていたら、足した段を進める（1a1 が使用中なら 1a2）。
- 旧番号（2026-10-27 までの Branch の形の番号）から新しい番号への変換は `migrate_id`。
  先頭の数字はそのまま、その後ろに a を足し、元の段は文字→数字・数字→文字に置き換える（1 → 1a、1a → 1a1、1d1 → 1a4a）。
  親子の関係（Branch）は保たれる（1a の子 1a1 は 1a1 の子 1a1a になる）。
"""
from __future__ import annotations

import re

# 区画の数字 + 交互の段（文字の段は末尾だけ連続してよい）
ID_RE = re.compile(r'[1-9]\d*(?:[a-z]+\d+)*(?:[a-z]+)?')
_SEG_RE = re.compile(r'\d+|[a-z]+')


def letters(number: int) -> str:
    """1 → a, 26 → z, 27 → aa（bijective base-26）。"""
    if number < 1:
        raise ValueError('letters: number must be >= 1')
    out = ''
    while number:
        number, digit = divmod(number - 1, 26)
        out = chr(97 + digit) + out
    return out


def letter_value(s: str) -> int:
    """a → 1, z → 26, aa → 27。"""
    n = 0
    for c in s:
        n = n * 26 + (ord(c) - 96)
    return n


def is_valid(ident: str) -> bool:
    return bool(ident) and ID_RE.fullmatch(ident) is not None


def segments(ident: str) -> list[tuple[bool, str]]:
    """段の列。(数字の段か, 文字列)。先頭の区画の数字も 1 つの数字の段。"""
    if not is_valid(ident):
        raise ValueError(f'不正な番号: {ident!r}')
    return [(seg.isdigit(), seg) for seg in _SEG_RE.findall(ident)]


def sort_key(ident: str) -> tuple:
    """並び順。段ごとに比べる（数字の段は数値、文字の段は bijective の値）。"""
    key = []
    for is_num, seg in segments(ident):
        key.append((0, int(seg)) if is_num else (1, letter_value(seg)))
    return tuple(key)


def parent(ident: str) -> str:
    """最後の段を外した番号。区画だけ（1）の親は ''。"""
    segs = segments(ident)
    if len(segs) <= 1:
        return ''
    return ''.join(s for _, s in segs[:-1])


def _bump(ident: str) -> str:
    """最後の段を 1 つ進める。"""
    segs = segments(ident)
    is_num, seg = segs[-1]
    head = ''.join(s for _, s in segs[:-1])
    if is_num:
        return head + str(int(seg) + 1)
    return head + letters(letter_value(seg) + 1)


def _free(candidate: str, used: set[str]) -> str:
    """使われていなければそのまま。使われていれば、最後の段を進めて空きを探す。"""
    while candidate in used:
        candidate = _bump(candidate)
    return candidate


def continuation(ident: str, used: set[str]) -> str:
    """ident の続き（同じ流れの次のノート）。"""
    segs = segments(ident)
    if segs[-1][0]:
        cand = _bump(ident)
    else:
        cand = ident + '1'
    return _free(cand, used)


def branch(ident: str, used: set[str]) -> str:
    """ident から分岐した子。使われた番号は避ける。"""
    last_is_num = segments(ident)[-1][0]
    cand = ident + ('a' if last_is_num else '1')
    return _free(cand, used)


def new_region(used_regions: set[int]) -> str:
    """新しい区画を始める番号（区画の数字の次。その最初のトピックは a）。"""
    n = max(used_regions, default=0) + 1
    return f'{n}a'


def region_of(ident: str) -> int:
    return int(segments(ident)[0][1])


def migrate_id(old: str) -> str:
    """旧番号 → 新番号（上の規則）。紙の印（PA-）付きの番号は変換しない（呼び出し側で除く）。"""
    if not re.fullmatch(r'[1-9]\d*(?:[a-z]+|\d+)*', old or ''):
        raise ValueError(f'旧い番号として解釈できない: {old!r}')
    m = re.match(r'(\d+)(.*)', old)
    region, rest = m.group(1), m.group(2)
    out = []
    for is_num, seg in (( s.isdigit(), s) for s in _SEG_RE.findall(rest)):
        if is_num:
            out.append(letters(int(seg)))
        else:
            out.append(str(letter_value(seg)))
    return region + 'a' + ''.join(out)
