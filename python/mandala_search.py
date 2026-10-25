"""曼荼羅の検索（s）の順位づけ。題・ファイル名（パス）・本文を、全角半角・大文字小文字・カタカナ/ひらがなの違いを
無視して探し、題とファイル名に合うものを先に、本文だけのものを後ろに並べる。語は全部に合う必要がある（AND）。
gs（vault 全体の全文検索）のように、ファイル名にだけ合うノート（題が日本語の index.md など）も見つかる。
厳密に合うものが無いときだけ、題・ファイル名に対して「文字が順に並んでいればよい」曖昧な一致も使う。"""
from __future__ import annotations

import unicodedata
from pathlib import Path
from typing import Callable, Iterable


def norm(s: str) -> str:
    """検索用の正規化: NFKC（全角半角をそろえる）・大文字小文字の無視・カタカナをひらがなに。"""
    s = unicodedata.normalize("NFKC", s).casefold()
    return "".join(chr(ord(c) - 0x60) if "ァ" <= c <= "ヶ" else c for c in s)


def _subseq(w: str, s: str) -> bool:
    it = iter(s)
    return all(c in it for c in w)


def _field_score(w: str, title: str, stem: str, path: str, fuzzy: bool) -> float:
    best = 0.0
    if stem == w:
        best = 95
    elif title == w:
        best = 100
    elif stem.startswith(w):
        best = 75
    elif title.startswith(w):
        best = 85
    elif w in title:
        best = 70
    elif w in path:
        best = 55
    elif fuzzy and len(w) >= 2 and (_subseq(w, title) or _subseq(w, stem)):
        best = 8
    return best


def rank(items: Iterable[tuple[str, str, Callable[[], str]]], words: list[str], limit: int = 200) -> list[str]:
    """items: (相対パス, 題, 本文を返す関数)。words を全部含むものを、順位の高い順に（相対パス）。"""
    ws = [norm(w) for w in words if w and w.strip()]
    if not ws:
        return []
    rows = []
    for rel, title, body_fn in items:
        t = norm(title)
        p = norm(rel)
        stem = norm(Path(rel).stem)
        rows.append((rel, title, t, stem, p, body_fn))
    for fuzzy in (False, True):
        hits = []
        for rel, title, t, stem, p, body_fn in rows:
            total = 0.0
            body = None
            ok = True
            for w in ws:
                s = _field_score(w, t, stem, p, fuzzy)
                if s <= 0:
                    if body is None:
                        try:
                            body = norm(body_fn())
                        except (OSError, UnicodeDecodeError):
                            body = ""
                    if w in body:
                        s = 10
                if s <= 0:
                    ok = False
                    break
                total += s
            if ok:
                hits.append((-total, title, rel))
        if hits:
            hits.sort()
            return [rel for _s, _t, rel in hits[:limit]]
    return []
