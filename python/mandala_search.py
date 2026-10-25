"""曼荼羅の検索（s）の順位づけ。題・ファイル名（パス）・本文を、全角半角・大文字小文字・カタカナ/ひらがなの違いを
無視して探し、題とファイル名に合うものを先に、本文だけのものを後ろに並べる。語は全部に合う必要がある（AND）。
gs（vault 全体の全文検索）のように、ファイル名にだけ合うノート（題が日本語の index.md など）も見つかる。
厳密に合うものが無いときだけ、題・ファイル名に対して「文字が順に並んでいればよい」曖昧な一致も使う。"""
from __future__ import annotations

from pathlib import Path
from typing import Callable, Iterable

import search_query as sq


def norm(s: str) -> str:
    """検索用の正規化（search_query.normalize と同じ）。"""
    return sq.normalize(s)


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


def rank(items: Iterable[tuple[str, str, Callable[[], str]]], query, limit: int = 200) -> list[str]:
    """items: (相対パス, 題, 本文を返す関数)。query（検索の書き方は search_query.py。単語のリストも可）に合うものを、順位の高い順に（相対パス）。
    OR で分けた組ごとに点を付け、いちばん高い点を使う。除外（-語）は題・ファイル名・本文のどれかにあれば、その組は外れる。"""
    if isinstance(query, (list, tuple)):
        query = " ".join(query)
    groups = sq.parse(query)
    if not groups:
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
            body = None

            def body_text():
                nonlocal body
                if body is None:
                    try:
                        body = norm(body_fn())
                    except (OSError, UnicodeDecodeError):
                        body = ""
                return body

            best = None
            for g in groups:
                # 除外: 題・ファイル名・本文のどれかに入っていたら、この組は外れる
                if any(norm(w) in t or norm(w) in p or norm(w) in body_text() for w in g.neg):
                    continue
                total = 0.0
                ok = True
                for w0 in g.pos:
                    w = norm(w0)
                    sc = _field_score(w, t, stem, p, fuzzy)
                    if sc <= 0 and w in body_text():
                        sc = 10
                    if sc <= 0:
                        ok = False
                        break
                    total += sc
                if ok and (best is None or total > best):
                    best = total
            if best is not None:
                hits.append((-best, title, rel))
        if hits:
            hits.sort()
            return [rel for _s, _t, rel in hits[:limit]]
        if not any(g.pos for g in groups):
            return []
    return []
