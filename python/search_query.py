"""検索の書き方（gs・s・m・x で共通）。Vim 側は autoload/gnosis/query.vim（同じ規則。test/search_query_cases.json を両方が通る）。

  AND   空白（半角・全角・タブ）                 ハーブ 栽培
  NOT   語の先頭の -（直後に文字が続くとき）      ハーブ -メモ        … `-` だけ・`a-b` の途中の - は、ふつうの文字
  OR    前後に空白のある |                        ハーブ | バジル      … AND より弱い: `a b | c` は (a かつ b) または c
  句    "…" で囲む（中の空白も含めて 1 つの語）    "育て 方"           … NOT は -"育て 方"。閉じていない " は最後まで
  文字  \\ の次の 1 文字をそのまま                 \\-foo  \\|  \\"       … 先頭の - や | を探したいときは、これか "…" で囲む

大文字小文字・全角半角（NFKC）・カタカナ/ひらがなの違いは、照らし合わせるとき（呼ぶ側）で無視する（normalize）。
何も入っていない（空）ときは「全部」に合う。
"""
from __future__ import annotations

import unicodedata
from dataclasses import dataclass, field

_SPACES = " \t　\n"


@dataclass
class Group:
    pos: list[str] = field(default_factory=list)
    neg: list[str] = field(default_factory=list)


_KANA = {c: c - 0x60 for c in range(ord("ァ"), ord("ヶ") + 1)}


def normalize(s: str) -> str:
    """照らす文字をそろえる: NFKC（全角半角）・大文字小文字・カタカナ→ひらがな。"""
    return unicodedata.normalize("NFKC", s).casefold().translate(_KANA)


def _tokens(q: str):
    """(種類, 文字) の並び。種類: 'word'（ふつうの語）/ 'or'（| だけの語）。NOT の印は先頭に付けた (neg, 文字) の形で返す。"""
    out = []
    i, n = 0, len(q)
    while i < n:
        if q[i] in _SPACES:
            i += 1
            continue
        neg = False
        raw_start = i
        buf = []
        quoted = False
        # 先頭の - （直後に空白でない文字が続くとき）は NOT
        if q[i] == "-" and i + 1 < n and q[i + 1] not in _SPACES:
            neg = True
            i += 1
        while i < n and (quoted or q[i] not in _SPACES):
            c = q[i]
            if c == "\\" and i + 1 < n:
                buf.append(q[i + 1])
                i += 2
                continue
            if c == '"':
                quoted = not quoted
                i += 1
                continue
            buf.append(c)
            i += 1
        word = "".join(buf)
        raw = q[raw_start:i]
        if raw == "|":
            out.append(("or", ""))
        elif word != "" or neg:
            # 単独の - は、ふつうの文字（neg にしない）
            if neg and word == "":
                out.append(("word", "-"))
            else:
                out.append(("neg" if neg else "pos", word))
    return out


def parse(q: str) -> list[Group]:
    """OR で分けた Group のリスト。空なら []。"""
    groups = [Group()]
    for kind, w in _tokens(q or ""):
        if kind == "or":
            if groups[-1].pos or groups[-1].neg:
                groups.append(Group())
        elif kind == "neg":
            groups[-1].neg.append(w)
        else:
            groups[-1].pos.append(w)
    return [g for g in groups if g.pos or g.neg]


def terms(q: str) -> list[str]:
    """色をつける語（肯定の語だけ。重複なし・書いた順）。"""
    seen, out = set(), []
    for g in parse(q):
        for w in g.pos:
            if w not in seen:
                seen.add(w)
                out.append(w)
    return out


def match(q: str, text: str) -> bool:
    """text が検索に合うか。空の検索は合う。"""
    gs = parse(q)
    if not gs:
        return True
    t = normalize(text)
    for g in gs:
        if all(normalize(w) in t for w in g.pos) and not any(normalize(w) in t for w in g.neg):
            return True
    return False
