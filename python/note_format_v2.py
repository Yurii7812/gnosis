#!/usr/bin/env python3
"""Gnosis ノート形式 v2 の parse / render / sync。

詳細仕様は repo ルートの NOTE_FORMAT.md。要点:

- ファイル名 = タイムスタンプのみ。front matter は time / title。
- 本文の後、``## Parent`` 見張り行から上側（これ＝このノートにとって そのノートが○○）。
- ``## Child`` 見張り行から下側（それ＝そのノートにとって このノートが○○）。
  行全体がそれだけ（コロンも中身も無い）。旧 v1 の ``Parent:``/``Child:``
  （コロン付き・直後にリンク）とは別物。``##`` なしの旧 v2 見張り
  （``Parent``/``Child``）も読める。
- 関係: 索引 / 前提 / 論点 / 見解 / 関連 / ノート（既定）/ 自由入力。
  `グループ` は選ばない ── 相手が `attribute: グループ` / `attribute: 小グループ`
  のどちらでも、選んだ関係に関わらず自分側は自動で `グループ:` になる。
  （旧 `attribute: カテゴリー` / `attribute: キーワード` は前方互換で読める。§ATTR_ALIASES）。
  `関連` は対称。並び順は グループ → 小グループ → 索引 → 前提 → 論点 → 見解 → 関連 → ノート。
  相手が `attribute: グループ` / `attribute: 小グループ` のノートなら、自分側の
  ラベルは値に関わらず常に `グループ:`（相手側の そっちにとって は書かれた関係のまま）。
  自分が `attribute: グループ` なら、相手側の そっちにとって も常に `グループ:`
  （サブ容器として）。自分が `attribute: 小グループ` の場合はこの上書きをしない ──
  相手の そっちにとって には書かれた関係がそのまま出る（小グループは「何に属して
  いるか」を見せるだけで、相手を自分の下位に置く容器ではないため）。
- ノード属性は front matter の `attribute: グループ` / `attribute: 小グループ`
  （容器ノート・サブグループの印）。無ければただのノート。
  論点 / 見解 等は宣言しない（関係とタイトルから分かる）。
- リンク 1 本は ``関係: [t](x.md)`` のインライン、2 本以上は ``関係:`` 改行のブロック。
- 上側が真実。下側は他ノートの上側から導出。上下どちらも編集でき、
  片面の追加 / 削除はもう片面へ反映される（``.pkm_sync_state_v2.json`` で判定）。
  ただしラベルの文言は自動でミラーしない（下記）。
- 本文（散文）中のリンクは、明示の関係が無ければ相手の下側（``### BackLink``）に
  裸のリンクとして現れる（下側の見出し自体がラベルなので ``バックリンク:`` は付けない）。
- 関係ラベルは方向性を持つことが多い（例: ``きっかけ:`` は A 視点の言葉で、
  B からそのままミラーすると意味が通らない）ため、``関連``（対称）と
  ``グループ``（attribute による強制）を除き自動ではミラーしない。
  上側・下側どちらの方向から書いても対称に扱う: 自分の側に既に何か書いて
  あればそれをそのまま使い、無ければ（＝相手側が先にそのペアを書いていた
  場合）``ノート`` はそのまま、それ以外は ``(ラベル):`` と括弧付きの
  既定値になる。一度その位置に行ができたら、以後 sync はラベルを変えない
  （表示名と同じ sticky な扱い。再パースするたびに読み直すだけなので
  自然に sticky になる）。
- リンク表示名は上側・下側とも同じ判定で追従するかどうかが決まる：今書かれて
  いる表示名が前回 sync 時点の相手のタイトルと同じ（＝手で変えていない）なら
  現タイトルへ追従、違っていれば（＝手で変えた）そのまま残す
  （``.pkm_title_state_v2.json`` で前回タイトルを記録）。

sync が書き換えるのは見張りコメント 2 行を持つノートだけ。旧 v1 / 旧 `---` /
日記 / 素の散文は触らない。旧形式の一括変換は `migrate` で明示的に行う。

CLI:
    note_format_v2.py update      ROOT
    note_format_v2.py update_one  FILE ROOT
    note_format_v2.py new         FILE ROOT [TITLE]
    note_format_v2.py migrate     ROOT [FILE]
    note_format_v2.py dupcheck    DIR_A DIR_B
"""
from __future__ import annotations

import contextlib
import datetime as _dt
import hashlib
import json
import os
import re
import sys
from pathlib import Path
from urllib.parse import unquote

try:
    import japanese_yomi as _jy
    from japanese_yomi import parse_yomi_map, set_yomi_map
except ImportError:  # 実行ディレクトリ以外から import されたとき
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import japanese_yomi as _jy
    from japanese_yomi import parse_yomi_map, set_yomi_map

RELATIONS: tuple[str, ...] = (
    "group", "索引", "前提", "論点", "見解", "ノート", "関連", "補足", "資料",
)
# 関係名の読み替え
RELATION_ALIASES: dict[str, str] = {
    "ワード": "キーワード",
    "グループ": "group",
    "小グループ": "group",
}
# ノード属性: `attribute: group`（容器ノートの印）。表記は英語 `group` に統一。
# 旧 グループ / 小グループ / カテゴリー / キーワード はすべて `group` として扱う。
ATTR_KEYS = ("attribute", "属性")
CATEGORY_ATTR = "group"  # attribute の値 / 内部ラベル
ATTR_ALIASES: dict[str, str] = {
    "グループ": CATEGORY_ATTR,
    "カテゴリー": CATEGORY_ATTR,
    "キーワード": CATEGORY_ATTR,
    "小グループ": CATEGORY_ATTR,
}
ATTR_LABELS: frozenset[str] = frozenset({CATEGORY_ATTR})  # attribute として使える値
# 対称関係: 上側には出さず、両ノートの下側に現れる。
SYMMETRIC: frozenset[str] = frozenset({"関連"})
BACKLINK = "バックリンク"

UP_MARK = "### Parent"
DOWN_MARK = "### BackLink"   # 旧 v2 の見張り（読み込みの判定用）。simple_sync の出力は BACKLINK_MARK
# 現行（simple_sync）の見張り。上側は `### Context`（旧 `### Parent`）と `### Group`。
# 旧 `### Parent` は parse だけが読み、sync が `### Context` へ移行する。
CONTEXT_MARK = "### Context"
GROUP_MARK = "Group:"
BRANCH_GROUP_HEAD = "BranchGroup:"
LEGACY_THIS_NOTE_GROUP_HEAD = "ThisNoteGroup:"  # 読み込み互換
LEGACY_GROUP_MARK = "### Group"  # 読み込みのみ。出力は Group: に統一する。
# Branch（Folgezettel 的な直接のブランチ）。`b` で明示したときだけ書かれる関係。
# 親は最大 1 つ（ParentBranch）、子は複数（ChildBranch）。Context / Related とは別の関係。
# 関係の見出しは、Group: / Context: と同じ「名前:」の形で書く（2026-10-15〜）。
# ノートの並び: BranchGroup: → Group: → ParentBranch: → Context:（ここまで本文の上、H1 の直後のブロック）
#   → 本文 → ChildBranch: → Related: → BackLink:（本文の下の節）。
# 旧形式の `### 名前` も読める（出力は「名前:」に統一する）。
PARENT_BRANCH_MARK = "ParentBranch:"
CHILD_BRANCH_MARK = "ChildBranch:"
RELATED_MARK = "Related:"
BACKLINK_MARK = "BackLink:"
PARENT_BRANCH_MARK_LEGACY = "### ParentBranch"
CHILD_BRANCH_MARK_LEGACY = "### ChildBranch"
RELATED_MARK_LEGACY = "### Related"
BACKLINK_MARK_LEGACY = "### BackLink"
# 旧見出し → 新しい見出し
LEGACY_TO_NEW_MARK = {
    PARENT_BRANCH_MARK_LEGACY: PARENT_BRANCH_MARK,
    CHILD_BRANCH_MARK_LEGACY: CHILD_BRANCH_MARK,
    RELATED_MARK_LEGACY: RELATED_MARK,
    BACKLINK_MARK_LEGACY: BACKLINK_MARK,
}
# Context は本文の冒頭（H1 の直後）の `Context:` ブロック（見出しではなく、ふつうのテキスト行 + 直下のリンク群）。
# 旧形式の `### Context` 節（旧 `### Parent`）も読める。
CONTEXT_HEAD = "Context:"

# 関係の節の並び順（sync が書き出す順。Context は本文の冒頭のブロックなので含まない。旧形式の節は互換のため読む）
SECTION_ORDER = (PARENT_BRANCH_MARK, CONTEXT_MARK, GROUP_MARK, CHILD_BRANCH_MARK,
                 RELATED_MARK, BACKLINK_MARK)
# 末尾の関係の節の見出し（新旧とも）。本文はこれより前。Group: / Context: は本文冒頭のブロックなので含まない。
ALL_SECTION_HEADS = (PARENT_BRANCH_MARK_LEGACY, CONTEXT_MARK, UP_MARK, LEGACY_GROUP_MARK,
                     CHILD_BRANCH_MARK, CHILD_BRANCH_MARK_LEGACY, RELATED_MARK, RELATED_MARK_LEGACY,
                     BACKLINK_MARK, BACKLINK_MARK_LEGACY)
# 旧見張り（新しい順）。parse だけが読む。render は新表記（## Parent / ## Child）に統一する。
LEGACY_UP_MARK3 = "Parent"  # `##` なしの旧 v2 見張り
LEGACY_DOWN_MARK3 = "Child"
LEGACY_UP_MARK2 = "<!-- こっちにとって -->"
LEGACY_DOWN_MARK2 = "<!-- そっちにとって -->"
LEGACY_UP_MARK = "<!-- している -->"
LEGACY_DOWN_MARK = "<!-- されている -->"

DIVIDER_RE = re.compile(r"^-{3,}\s*$")
# 任意の `語:` / `語;` 見出し（先頭が空白 / # / : / ; でない）。
# 散文除けは _looks_like_header で行う。`;` は「相手には自動で書かない」の意
# （§4）。ラベルは内部的には `;` を含んだ文字列として保持する（例: `きっかけ;`）。
HEADER_RE = re.compile(r"^([^\s:;#][^:;]*?)\s*([:;])\s*(.*)$")
# [表示]() 形式のリンク行（末尾に「 — 注釈」を許す）
LINK_LINE_RE = re.compile(r"^\s*\[((?:\\.|[^\]\\])*)\]\(([^)]+)\)\s*(?:—\s*(.*\S))?\s*$")
# 本文どこにでも現れるリンク（バックリンク判定用）
ANY_LINK_RE = re.compile(r"\[(?:\\.|[^\]\\])*\]\(([^)]+)\)")
# 旧 v1 の構造見出し
LEGACY_HDR_RE = re.compile(r"^(Parent|Child|Branch|BackLink|Back)\s*:\s*(.*)$", re.I)
# グループノートの判定（front matter の attribute / 属性）。simple_sync で
# ノートごとに再計算すると O(N²) になるため、コンパイル済みを使い回す。
_GROUP_ATTR_RE = re.compile(
    r"^\s*(?:attribute|属性)\s*:\s*"
    r"(?:group|グループ|小グループ|カテゴリー|キーワード)\s*$", re.M)

_EXTRA = "_extra"
_RESERVED = {_EXTRA, BACKLINK}


class Note:
    __slots__ = (
        "path", "fm", "title", "body", "up", "down", "managed",
        "down_raw", "down_rendered",
    )

    def __init__(self, path, fm, title, body, up, down, managed=True,
                 down_raw=None):
        self.path: Path = Path(path)
        self.fm: list[str] = fm
        self.title: str = title
        self.body: list[str] = body
        # managed=False: PKM 形式でない外部ファイル（日記など）。sync は書き換えない。
        self.managed: bool = managed
        self.up: dict[str, list[tuple[str, str, str | None]]] = up
        self.down: dict[str, list[tuple[str, str, str | None]]] = down
        # 下側（Child）の生の行。位置を保存したまま再描画するために保持する。
        self.down_raw: list[str] | None = down_raw
        # sync が位置保存で組み立てた下側の確定行（None なら通常描画）。
        self.down_rendered: list[str] | None = None


# ---------------------------------------------------------------------------
# parse
# ---------------------------------------------------------------------------

def _split_front_matter(lines: list[str]) -> tuple[list[str], list[str]]:
    if lines and lines[0].strip() == "---":
        for i in range(1, len(lines)):
            if lines[i].strip() == "---":
                return lines[: i + 1], lines[i + 1:]
    return [], list(lines)


def _title_of(fm: list[str], rest: list[str], stem: str) -> str:
    """題。先頭の `# 見出し`（H1）が正。H1 が無い古いノートだけ、front matter の title: を使う（無ければファイル名）。"""
    for ln, fz in zip(rest, _fenced(rest)):
        if not fz:
            m = re.match(r"^#\s+(\S.*?)\s*#*\s*$", ln)
            if m:
                return m.group(1).strip()
    return _fm_title(fm) or stem


def _fm_title(fm: list[str]) -> str:
    for ln in fm:
        m = re.match(r"^\s*title\s*:\s*(.+?)\s*$", ln)
        if m:
            return m.group(1)
    return ""


def _fm_attr(fm: list[str]) -> str:
    keys = "|".join(ATTR_KEYS)
    for ln in fm:
        m = re.match(rf"^\s*(?:{keys})\s*:\s*(.+?)\s*$", ln)
        if m:
            v = m.group(1).strip().strip("\"'")
            return ATTR_ALIASES.get(v, v)
    return ""


def _looks_like_header(m: re.Match, lines: list[str], idx: int) -> bool:
    inline = m.group(3).strip()
    # `語:: …` / `語:; …` は、余分な `:` / `;` 1 文字を落としてから見る。
    if inline.startswith(":") or inline.startswith(";"):
        inline = inline[1:].lstrip()
    if inline:
        return bool(LINK_LINE_RE.match(inline))
    for j in range(idx + 1, min(idx + 4, len(lines))):
        s = lines[j].strip()
        if s == "":
            continue
        return bool(LINK_LINE_RE.match(s))
    return False


def _header_label(m: re.Match) -> str:
    """HEADER_RE のマッチから内部ラベル文字列を作る。`;` 終端なら末尾に `;` を
    残す（例: `きっかけ;` -> `きっかけ;`）。エイリアス変換は素の語に対して行う。

    `group` だけは位置（先頭ブロックの裸リンク）でも表せる。明示的に `group:`
    と書いた場合は、裸（位置）の `group` と区別して `group:` を残す ── そう
    しないと `:` の「相手に `(group)` でミラー」が効かなくなるため。
    """
    name = RELATION_ALIASES.get(m.group(1).strip(), m.group(1).strip())
    if m.group(2) == ";":
        return name + ";"
    rest = m.group(3).lstrip()
    if rest.startswith(":"):
        return name + "::"   # `語::` … 両方の同じセクションに `語:`
    if rest.startswith(";"):
        return name + ":;"   # `語:;` … 相手側も `語:;`（括弧なし・終端）
    return name + ":" if name == CATEGORY_ATTR else name


def _parse_sections(lines: list[str], allow_body: bool):
    body: list[str] = []
    sections: dict[str, list] = {}
    cur: str | None = None
    seen_header = False
    i, n = 0, len(lines)
    while i < n:
        ln = lines[i]
        s = ln.strip()
        m = HEADER_RE.match(s)
        if m and _looks_like_header(m, lines, i):
            cur = _header_label(m)
            seen_header = True
            sections.setdefault(cur, [])
            inline = m.group(3).strip()
            if inline.startswith(":") or inline.startswith(";"):
                inline = inline[1:].lstrip()  # `語:: …` / `語:; …` の余分な 1 文字
            lm = LINK_LINE_RE.match(inline)
            if lm:
                sections[cur].append((lm.group(1), lm.group(2), lm.group(3) or None))
            i += 1
            continue
        lm = LINK_LINE_RE.match(s)
        if lm and cur is None and not allow_body:
            # 見張りの直下にラベル無しで書かれたリンクは、既定の `ノート:`
            # （特別な役割の無い関係）とみなす。手でリンクだけ書いた子/親も
            # 相方へちゃんと反映されるようにするため（旧 v1 的な書き方の救済）。
            cur = "ノート"
            sections.setdefault(cur, [])
            sections[cur].append((lm.group(1), lm.group(2), lm.group(3) or None))
            i += 1
            continue
        if lm and cur is not None:
            sections[cur].append((lm.group(1), lm.group(2), lm.group(3) or None))
            i += 1
            continue
        cur = None
        if s == "":
            if allow_body and not seen_header:
                body.append(ln)
        elif allow_body and not seen_header:
            body.append(ln)
        else:
            sections.setdefault(_EXTRA, []).append(ln)
        i += 1
    while body and body[-1].strip() == "":
        body.pop()
    return body, sections


def _has_relation_header(lines: list[str]) -> bool:
    for j, l in enumerate(lines):
        m = HEADER_RE.match(l.strip())
        if m and _looks_like_header(m, lines, j):
            return True
    return False


def _route_legacy_link(up: dict, ti: str, tg: str, ann: str | None) -> None:
    base = tg.split("#", 1)[0].rsplit("/", 1)[-1].lower()
    kind = CATEGORY_ATTR if base in ("index.md", "index") else "関連"  # v1 の Index -> グループ
    up.setdefault(kind, [])
    if all(e[1] != tg for e in up[kind]):
        up[kind].append((ti, tg, ann))


def _migrate_legacy(lines: list[str]):
    """旧 v1（Parent:/Child:/BackLink:）を v2 の形へ寄せる。

    Parent/Child/Branch のリンク -> ``関連:``、``[Index](index.md)`` -> ``グループ:``。
    BackLink は捨てる（sync が下側に再生成する）。リンクは失わない。
    """
    body: list[str] = []
    up: dict[str, list] = {}
    down: dict[str, list] = {}
    zone: object = None  # None | "up" | "back" | ("rel", 関係)
    seen = False
    for idx, ln in enumerate(lines):
        s = ln.strip()
        lm = LINK_LINE_RE.match(s)
        if lm and lm.group(2).split("#", 1)[0].rsplit("/", 1)[-1].lower() in ("index.md", "index"):
            _route_legacy_link(up, lm.group(1), lm.group(2), lm.group(3) or None)
            continue
        lg = LEGACY_HDR_RE.match(s)
        if lg:
            seen = True
            name = lg.group(1).lower()
            zone = "back" if name in ("backlink", "back") else "up"
            inln = LINK_LINE_RE.match(lg.group(2).strip())
            if inln and zone == "up":
                _route_legacy_link(up, inln.group(1), inln.group(2), inln.group(3) or None)
            continue
        tm = HEADER_RE.match(s)
        if tm and _looks_like_header(tm, lines, idx):
            seen = True
            _r = _header_label(tm)
            zone = ("rel", _r)
            up.setdefault(zone[1], [])
            inln = LINK_LINE_RE.match(tm.group(3).strip())
            if inln:
                up[zone[1]].append((inln.group(1), inln.group(2), inln.group(3) or None))
            continue
        if lm:
            if zone == "up":
                _route_legacy_link(up, lm.group(1), lm.group(2), lm.group(3) or None)
            elif isinstance(zone, tuple):
                up[zone[1]].append((lm.group(1), lm.group(2), lm.group(3) or None))
            continue
        if not seen:
            body.append(ln)
    while body and body[-1].strip() == "":
        body.pop()
    return body, up, down


def parse_note(path, text: str | None = None) -> Note:
    p = Path(path)
    if text is None:
        text = p.read_text(encoding="utf-8")
    raw = text.split("\n")
    fm, rest = _split_front_matter(raw)
    title = _title_of(fm, rest, p.stem)

    stripped = [ln.strip() for ln in rest]

    # sync が触るのは見張り 2 行を持つファイルだけ。
    # それ以外（旧 v1 / 旧 --- / 日記 / 素の散文）は managed=False で読むだけ。
    # 見張りは新表記（## Parent / ## Child）・旧表記（`##` なしの Parent/Child）・
    # 旧表記（こっちにとって/そっちにとって の HTML コメント）・さらに旧い表記
    # （している/されている）のどれでも読める。
    # render は常に新表記で書き直す（＝次の sync で自動移行）。
    up_mark = UP_MARK if UP_MARK in stripped else (
        LEGACY_UP_MARK3 if LEGACY_UP_MARK3 in stripped else (
            LEGACY_UP_MARK2 if LEGACY_UP_MARK2 in stripped else (
                LEGACY_UP_MARK if LEGACY_UP_MARK in stripped else None)))
    down_mark = DOWN_MARK if DOWN_MARK in stripped else (
        LEGACY_DOWN_MARK3 if LEGACY_DOWN_MARK3 in stripped else (
            LEGACY_DOWN_MARK2 if LEGACY_DOWN_MARK2 in stripped else (
                LEGACY_DOWN_MARK if LEGACY_DOWN_MARK in stripped else None)))
    marked = up_mark is not None and down_mark is not None
    frozen = bool(re.search(
        r"^\s*(pkm\s*:\s*raw|sync\s*:\s*(?:false|off|no))\s*$",
        "\n".join(fm), re.I | re.M))

    if not marked or frozen:
        body = list(rest)
        while body and body[-1].strip() == "":
            body.pop()
        return Note(p, fm, title, body, {}, {}, managed=False)

    u = len(stripped) - 1 - stripped[::-1].index(up_mark)
    d = len(stripped) - 1 - stripped[::-1].index(down_mark)
    if u > d:
        u = stripped.index(up_mark)
    # 本文は 1 行も削らない。見張りの直前に空いている行は「書くための余白」で、
    # テンプレートが意図して置いたもの（カーソルはそこに来る）。
    body = list(rest[:u])
    _, up = _parse_sections(rest[u + 1: d], allow_body=False)
    _, down = _parse_sections(rest[d + 1:], allow_body=False)
    # 下側の生の行を保持（位置を変えずに再描画するため）。
    return Note(p, fm, title, body, up, down, down_raw=list(rest[d + 1:]))


def migrate_note(text: str, path: str = "note.md") -> str | None:
    """旧形式（v1 の Parent:/Child:/BackLink: / 旧 `---` v2）を v2 テキストへ変換。

    既に見張りコメントがある / 旧形式と認識できない場合は None。
    """
    raw = text.split("\n")
    fm, rest = _split_front_matter(raw)
    stripped = [ln.strip() for ln in rest]
    if (UP_MARK in stripped and DOWN_MARK in stripped) or (
            LEGACY_UP_MARK3 in stripped and LEGACY_DOWN_MARK3 in stripped) or (
            LEGACY_UP_MARK2 in stripped and LEGACY_DOWN_MARK2 in stripped) or (
            LEGACY_UP_MARK in stripped and LEGACY_DOWN_MARK in stripped):
        return None
    title = _title_of(fm, rest, Path(path).stem)
    div_idx = [i for i, s in enumerate(stripped) if DIVIDER_RE.match(s)]

    if len(div_idx) >= 2 and (
        _has_relation_header(rest[div_idx[-2] + 1:])
        or all(x == "" for x in stripped[div_idx[-2] + 1:])
    ):
        body_lines = rest[:div_idx[-2]]
        _, up = _parse_sections(rest[div_idx[-2] + 1: div_idx[-1]], allow_body=False)
        _, down = _parse_sections(rest[div_idx[-1] + 1:], allow_body=False)
    elif len(div_idx) == 1 and (
        _has_relation_header(rest[div_idx[0] + 1:])
        or all(x == "" for x in stripped[div_idx[0] + 1:])
    ):
        body_lines = rest[:div_idx[0]]
        _, up = _parse_sections(rest[div_idx[0] + 1:], allow_body=False)
        down = {}
    elif any(LEGACY_HDR_RE.match(s) for s in stripped):
        body_lines, up, down = _migrate_legacy(rest)
    else:
        return None

    body = list(body_lines)
    while body and body[-1].strip() == "":
        body.pop()
    return render_note(Note(Path(path), fm, title, body, up, down))


_FENCE_RE = re.compile(r"^\s{0,3}(`{3,}|~{3,})")
_INLINE_CODE_RE = re.compile(r"(`+)(?:(?!\1).)+?\1|(`+)[^`]*$")


# Context: より上に来る、本文の上の先頭のブロックの見出し（並び: BranchGroup → Group → ParentBranch → Context）
_ABOVE_CONTEXT_HEADS = ("ParentBranch:", "BranchGroup:", "ThisNoteGroup:", "Group:")


def find_context_block(lines: list[str], start: int = 0) -> tuple[int, int] | None:
    """新形式の Context ブロックの (`Context:` の行, リンクの最後の行)（0 始まり）。無ければ None。
    H1 の直後にあるものだけ（間は空行と、上に来る先頭のブロック ParentBranch: / BranchGroup: / Group: だけ。
    H1 が無ければ先頭）。リンク行が続く間がブロック。コードブロックの中は見ない。"""
    fenced = _fenced(lines)
    seen_h1 = False
    i = start
    while i < len(lines):
        if fenced[i]:
            return None
        s = lines[i].strip()
        if s == CONTEXT_HEAD:
            j = i
            while j + 1 < len(lines) and not fenced[j + 1] and _SIMPLE_LINK_LINE_RE.match(lines[j + 1]):
                j += 1
            return (i, j)
        if s == "":
            i += 1
            continue
        if re.match(r"^#\s+\S", lines[i]) and not seen_h1:
            seen_h1 = True
            i += 1
            continue
        if s in _ABOVE_CONTEXT_HEADS:
            i += 1
            while i < len(lines) and not fenced[i] and _SIMPLE_LINK_LINE_RE.match(lines[i]):
                i += 1
            continue
        return None
    return None


def above_context_end(lines: list[str], start: int = 0) -> int | None:
    """H1 の直後に続く、Context: より上の先頭のブロック（ParentBranch: / BranchGroup: / Group:）の終わりの次の行。
    そういうブロックが無ければ None。Context: を新しく作るときは、ここに置く。"""
    fenced = _fenced(lines)
    seen_h1 = False
    end = None
    i = start
    while i < len(lines):
        if fenced[i]:
            break
        s = lines[i].strip()
        if s == "":
            i += 1
            continue
        if re.match(r"^#\s+\S", lines[i]) and not seen_h1:
            seen_h1 = True
            i += 1
            continue
        if s in _ABOVE_CONTEXT_HEADS:
            i += 1
            while i < len(lines) and not fenced[i] and _SIMPLE_LINK_LINE_RE.match(lines[i]):
                i += 1
            end = i
            continue
        break
    return end


def _fenced(lines: list[str]) -> list[bool]:
    """各行が ``` / ~~~ で囲んだコードブロック（囲みの行を含む）の中か。"""
    out: list[bool] = []
    mark = None
    for ln in lines:
        m = _FENCE_RE.match(ln)
        if mark is None:
            if m:
                mark = m.group(1)[0] * 3
                out.append(True)
            else:
                out.append(False)
        else:
            out.append(True)
            if m and m.group(1)[0] == mark[0] and ln.strip().strip(mark[0]) == "":
                mark = None
    return out


def _code_spans(ln: str) -> list[tuple[int, int]]:
    """行の中の `インラインコード` の範囲。"""
    return [m.span() for m in _INLINE_CODE_RE.finditer(ln)]


def _link_iter(rx, ln: str):
    """行の中のリンク記法 [..](..) のうち、`コード` の外にあるものだけ。"""
    spans = _code_spans(ln)
    for m in rx.finditer(ln):
        if not any(a <= m.start() < b for a, b in spans):
            yield m


def _link_sub(rx, repl, ln: str) -> str:
    """rx.sub と同じだが、`コード` の中のリンク記法は変えない。"""
    spans = _code_spans(ln)

    def f(m):
        if any(a <= m.start() < b for a, b in spans):
            return m.group(0)
        return repl(m)
    return rx.sub(f, ln)


def _links_in(lines: list[str]) -> list[str]:
    out: list[str] = []
    for ln, fz in zip(lines, _fenced(lines)):
        if fz:
            continue
        for m in _link_iter(ANY_LINK_RE, ln):
            t = m.group(1).split("#", 1)[0].strip()
            if t.lower().endswith(".md"):
                out.append(t)
    return out


# ---------------------------------------------------------------------------
# render
# ---------------------------------------------------------------------------

def _render_section(t: str, entries: list[tuple[str, str, str | None]]) -> list[str]:
    """既定の `ノート` はラベルを書かず、リンクだけを裸で並べる
    （`ノート:` 見出しは不要、という方針）。それ以外はブロック形で書く。

        ラベル:
        [表示名](target.md)

    1 本でもインラインにしない。増えたときに行の形が変わらず、追記が
    「1 行足すだけ」で済むため。読み込み側はインライン形も受け付ける。
    """
    if not entries:
        return []
    out: list[str] = []
    # 既定の `ノート` と強制ラベルの `グループ` は、位置（ブロック順）で
    # 分かるので見出しを書かない。`グループ;` / `ノート;` のように `;` を
    # 明示した時だけ見出しを残す（自動ミラー抑止の意思表示のため）。
    if t not in ("ノート", CATEGORY_ATTR):
        if t.endswith("::"):
            out.append(t[:-2] + ":")   # `語::` は `語:` として出す（両側）
        elif t.endswith(":;") or t.endswith(";") or t.endswith(":"):
            out.append(t)              # `語:;` / `語;` / `group:` はそのまま
        else:
            out.append(f"{t}:")
    for ti, tg, ann in entries:
        s = f"[{ti}]({tg})"
        out.append(s + f" — {ann}" if ann else s)
    return out


def _join_blocks(blocks: list[list[str]]) -> list[str]:
    """ブロック（連続する行のまとまり）を空行 1 つで区切って繋ぐ。"""
    out: list[str] = []
    for i, blk in enumerate(blocks):
        if not blk:
            continue
        if i > 0:
            out.append("")
        out += blk
    return out


def _render_group(d: dict[str, list], is_down: bool = False) -> list[str]:
    """上側（Parent）は **グループ（`group`）を先頭に固定**するだけ。それ以外
    のブロック（既定の `ノート` や手で書いた `ワード:`）の並びは d の順序
    （＝ユーザーが最後に書いた/並べ替えた順）をそのまま尊重する。下側（Child）
    も d の順序を尊重する（`関連` は対称、`バックリンク` は最後）。どちらも
    ブロックの間は空行 1 つで区切る（既定の `ノート` は見出しが無いので、
    空行が無いと前のブロックのリンクと区別できないため）。
    """
    if is_down:
        blocks = [
            _render_section(t, d[t])
            for t in d if t not in _RESERVED and d.get(t)
        ]
        if d.get(BACKLINK):
            # `### BackLink` 見出し自体がラベルなので、内側に `バックリンク:` は付けない
            back_entries = []
            for ti, tg, ann in d[BACKLINK]:
                s = f"[{ti}]({tg})"
                back_entries.append(s + f" — {ann}" if ann else s)
            blocks.append(back_entries)
        out = _join_blocks(blocks)
        extra = list(d.get(_EXTRA, []))
        if extra:
            if out:
                out.append("")
            out += extra
        return out

    # グループだけ先頭に固定。それ以外は d の順序（ユーザーの並び）のまま。
    labels: list[str] = []
    if d.get(CATEGORY_ATTR):
        labels.append(CATEGORY_ATTR)
    for t in d:
        if t in _RESERVED or t == CATEGORY_ATTR:
            continue
        if d.get(t):
            labels.append(t)
    blocks = [_render_section(t, d[t]) for t in labels]
    out = _join_blocks(blocks)
    extra = list(d.get(_EXTRA, []))
    if extra:
        if out:
            out.append("")
        out += extra
    return out


def _squeeze_blanks(lines: list[str]) -> list[str]:
    res: list[str] = []
    prev_blank = False
    for ln in lines:
        blank = ln.strip() == ""
        if blank and prev_blank:
            continue
        res.append(ln)
        prev_blank = blank
    return res


def _render_down_preserving(note: Note, key_fn) -> list[str] | None:
    """Child（下側）をできるだけ「元のまま」に保って組み立てる。

    空行・見出し・並びをそのまま残し、リンク行は位置を動かさず表示名だけ更新。
    見出しは必要なら同じ位置で書き換える（既定に戻る場合は見出し行を外す）。
    消えた関係の行だけ取り除き、新しい関係の行は末尾に足す。並べ替え・
    まとめ直しは一切しない。位置はユーザーが h/Enter/o/p と手編集で決める。
    """
    raw = note.down_raw
    if raw is None:
        return None

    def key(tg: str):
        k = key_fn(tg)
        return k if k is not None else ("raw", tg)

    desired: dict[object, tuple[str, str, str | None, str]] = {}
    for label, entries in note.down.items():
        if label == _EXTRA:
            continue
        for disp, tg, ann in entries:
            desired.setdefault(key(tg), (disp, tg, ann, label))

    def header_line(label: str) -> str | None:
        if label in ("ノート", CATEGORY_ATTR, BACKLINK):
            return None  # 見出しを書かない（位置で表す裸リンク / BackLink は親見出し）
        if label.endswith("::"):
            return label[:-2] + ":"   # `語::` は `語:` で出す（両側）
        if label.endswith(":;") or label.endswith(";") or label.endswith(":"):
            return label
        return f"{label}:"

    out: list[str] = []
    used: set = set()
    prev_label: str | None = None  # 直前に出したリンクのラベル

    def emit_link(disp: str, tg: str, ann: str | None, label: str) -> None:
        nonlocal prev_label
        if label != prev_label:
            hl = header_line(label)
            if hl is not None:
                out.append(hl)
            prev_label = label
        t = f"[{disp}]({tg})"
        out.append(t + f" — {ann}" if ann else t)

    for i, ln in enumerate(raw):
        s = ln.strip()
        m = HEADER_RE.match(s)
        lm = None
        if m and _looks_like_header(m, raw, i):
            # 見出し行。インラインのリンクがあればそれを 1 本として扱う。
            rest = m.group(3).lstrip()
            if rest.startswith(":") or rest.startswith(";"):
                rest = rest[1:].lstrip()
            lm = LINK_LINE_RE.match(rest)
            if lm is None:
                continue  # 見出しのみ（リンクは以降の行）。見出しは出し直す
        else:
            lm = LINK_LINE_RE.match(s)
        if lm:
            k = key_fn(lm.group(2))
            if k is not None and k in desired and k not in used:
                used.add(k)
                disp, _tg, ann, label = desired[k]
                ann2 = ann if ann else (lm.group(3) or None)
                emit_link(disp, lm.group(2), ann2, label)
                continue
            if k is not None:
                continue  # 消えた関係 / 重複
            out.append(ln)  # 解決できないリンクはそのまま残す
            prev_label = None
            continue
        # リンク行以外（空行・散文）
        out.append(ln)
        if s != "":
            prev_label = None  # 散文などでブロックが切れる
        for mm in _link_iter(ANY_LINK_RE, ln):
            kk = key_fn(mm.group(1))
            if kk is not None and kk in desired:
                used.add(kk)

    for k, (disp, tg, ann, label) in desired.items():
        if k in used:
            continue
        used.add(k)
        if label != prev_label and out and out[-1].strip() != "":
            out.append("")
        emit_link(disp, tg, ann, label)
    # 先頭の空行は落とす（### BackLink の直後に空行を入れない）
    while out and out[0].strip() == "":
        out.pop(0)
    return out


def render_note(note: Note) -> str:
    """本文はユーザーのもの。空行を含めてそのまま通す。

    整形するのは見張りコメント以降（関係セクション）だけ。本文の空行を
    潰すと、テンプレートが置いた「書くための余白」が毎回消えてしまう。
    """
    out: list[str] = list(note.fm)
    body = list(note.body)
    # front matter の直後は 1 行空ける（本文が既に空行始まりならそれを使う）
    if not body or body[0].strip() != "":
        out.append("")
    out += body

    # 本文 → こっちにとって見張り → 上側 → そっちにとって見張り → 下側
    # 本文と ### Parent の間には空行を入れない（2026-10-09 指示）
    out.append(UP_MARK)
    out += _squeeze_blanks(_render_group(note.up))
    out.append(DOWN_MARK)
    if note.down_rendered is not None:
        # sync が位置保存で組み立てた生の下側をそのまま使う（並べ替えない）。
        out += note.down_rendered
    else:
        out += _squeeze_blanks(_render_group(note.down, is_down=True))

    while out and out[-1].strip() == "":
        out.pop()
    return "\n".join(out) + "\n"


# ---------------------------------------------------------------------------
# resolution helpers
# ---------------------------------------------------------------------------

EXPAND_TMP_DIR = "_tmp"  # 旧 \e 出力（2026-10-06 以前）。今は \e/\se とも .trash。_iter_md が念のため除外。


def _iter_md(root: Path):
    # ドット始まり（.git・.undo・.trash・.crypt など）の中は降りない。暗号化 vault では、そこを数えるだけで遅くなる
    found = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if not d.startswith(".") and d != EXPAND_TMP_DIR]
        for name in filenames:
            if name.endswith(".md") and not name.startswith("."):
                found.append(Path(dirpath) / name)
    yield from sorted(found)


def _index(root: Path) -> dict[str, list[Path]]:
    by_name: dict[str, list[Path]] = {}
    for p in _iter_md(root):
        rp = p.resolve()
        by_name.setdefault(p.name, []).append(rp)
        by_name.setdefault(p.stem, []).append(rp)
    return by_name


def _resolve(target: str, note_dir: Path, root: Path, by_name: dict[str, list[Path]]) -> Path | None:
    t = target.split("#", 1)[0].strip()
    if not t or "://" in t:
        return None
    cand = note_dir / t
    try:
        cand = cand.resolve()
    except OSError:
        cand = None
    if cand is not None and cand.suffix.lower() == ".md" and cand.exists():
        return cand
    key = Path(t).name
    lst = by_name.get(key) or by_name.get(key[:-3] if key.endswith(".md") else key)
    if lst:
        uniq = set(lst)
        if len(uniq) == 1:
            return next(iter(uniq))
    return None


def _rel(from_dir: Path, target: Path) -> str:
    return os.path.relpath(target, from_dir).replace(os.sep, "/")


# ---------------------------------------------------------------------------
# sync
# ---------------------------------------------------------------------------

_STATE_FILE = ".pkm_sync_state_v2.json"
# 前回 sync 時点での各ノートのタイトル。リンク表示名を「追従させるか、打った
# 通り残すか」の判定に使う（_tracked_disp）。
_TITLE_STATE_FILE = ".pkm_title_state_v2.json"
Rel = tuple[str, str, str]  # (src_id, type, tgt_id)  id = root からの相対 posix パス


_ZK_IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".tif", ".tiff", ".bmp", ".webp"}
_ZK_ID_RE = re.compile(r"^(?:[A-Z]{1,4}-)?\d+(?:[a-z]+\d+)*[a-z]*(?:-.+)?$")
_ZK_PREFIX_RE = re.compile(r"^[A-Z]{1,4}-(?=\d)")
_ZK_DIARY_RE = re.compile(r"^(\d{4})-(\d{2})-(\d{2})-(?:MO|TU|WE|TH|FR|SA|SU)$")
_ZK_IMG_LINE = re.compile(r"^!\[(?:\\.|[^\]\\])*\]\(([^)\s]+)\)\s*$")


def _zk_note_images(title: str, body) -> list[str]:
    """紙PKMのノート（スキャン/トピック/紙の日記）なら、削除に合わせて退避する画像名を返す。

    判定は front matter の目印ではなく title と画像の参照による:
    - スキャン / トピック … title が `ID` / `ID-トピック名` で、本文に title と同じ名前の画像 `![](<title>.<ext>)` がある
    - 紙の日記 … title が `YYYY-MM-DD-曜日2文字` で、本文に `paper-diary-YYYYMMDD-N.<ext>` の画像がある
    ID らしい title だけで画像を参照していない普通のノートは対象にしない。"""
    names = []
    for ln in body or []:
        m = _ZK_IMG_LINE.match(ln.strip())
        if m:
            names.append(Path(m.group(1)).name)
    if not names:
        return []
    out = []
    dm = _ZK_DIARY_RE.match(title or "")
    for nm in names:
        stem, ext = os.path.splitext(nm)
        if ext.lower() not in _ZK_IMAGE_EXTS:
            continue
        # 題は `PA-1a2`（印つき）か `1a2`。画像は題と同じ名前か、印を除いた名前（旧い画像 `1a2.jpg` を持つ `PA-1a2`）
        if _ZK_ID_RE.match(title or "") and (stem == title or stem == _ZK_PREFIX_RE.sub("", title or "")):
            out.append(nm)
        elif dm and stem.startswith("paper-diary-" + "".join(dm.groups()) + "-"):
            out.append(nm)
    return out


def _trash_zk_note_images(root: Path, cache: dict, keys_now: set, alive_bodies=None) -> int:
    """Zettelkasten ノートの削除に合わせて画像も .trash へ退避する（2026-10-09）。

    前回パースキャッシュにあって今回ディスクに無いノート（＝削除/ゴミ箱移動）について、
    title と本文の画像参照で紙PKMのノートと判定し（_zk_note_images）、同じフォルダの
    その画像を vault の `.trash` に <時刻>_ 接頭付きで退避する。旧ノートの
    `folgezettel:` / `paper_topic:` も互換として読む。生きている他のノートが同じ画像を参照して
    いれば動かさない。紙PKM以外のノートの画像には触らない。戻り値は退避した画像数。
    alive_bodies: 生きているノートの [(ノートのフォルダ, title, 本文)]（持ち主が残っている画像を守る）。
    """
    from datetime import datetime as _dt

    now_s = _dt.now().strftime("%Y%m%d-%H%M%S")
    trashed = 0
    trash_dir = root / ".trash"
    in_use: set[str] = set()
    # 生きている紙PKMのノート（スキャン/トピック/日記）が自分の画像として持っているものは動かさない。
    # （専用ノート folgezettel-Index-N のように画像を並べるだけのノートは持ち主ではない）
    for folder, title, body in alive_bodies or []:
        for nm in _zk_note_images(title, body):
            in_use.add(os.path.normpath(os.path.join(str(folder), nm)))
    for key, ent in cache.items():
        if key in keys_now or not isinstance(ent, list) or len(ent) < 4:
            continue
        fm = ent[1] if isinstance(ent[1], list) else []
        title = ent[2] if isinstance(ent[2], str) else ""
        note_path = root / key  # key は vault 相対パス（_nid 由来）
        folder = note_path.parent
        imgs = _zk_note_images(title, ent[3] if isinstance(ent[3], list) else [])
        if not imgs:
            # 旧ノート（目印の front matter が残っている）の互換: title と同じ名前の画像を探す
            legacy = None
            for ln in fm:
                s = ln.strip()
                if s.startswith("folgezettel:"):
                    # The live digital Folgezettel field is independent of title;
                    # only the retired paper marker used title-equal IDs.
                    candidate = s.split(":", 1)[1].strip()
                    if candidate == title:
                        legacy = candidate
                    break
            if legacy is None and any(ln.strip().startswith("paper_topic:") for ln in fm):
                legacy = title
            if legacy:
                imgs = [legacy + e for e in _ZK_IMAGE_EXTS]
        for nm in imgs:
            img = folder / nm
            if not img.is_file() or os.path.normpath(str(img)) in in_use:
                continue
            try:
                trash_dir.mkdir(parents=True, exist_ok=True)
                dest = trash_dir / f"{now_s}_{img.name}"
                i = 0
                while dest.exists():
                    i += 1
                    dest = trash_dir / f"{now_s}-{i}_{img.name}"
                img.rename(dest)
                trashed += 1
            except OSError:
                pass
    return trashed


def _nid(path: Path, root: Path) -> str | None:
    # pathlib の relative_to は 1 万ノートで秒単位になり得るため、まず文字列
    # 演算（relpath）で済ませる。root 内で解決済みならこれで足りる。
    rel = os.path.relpath(str(path), str(root))
    if not rel.startswith(".."):
        return rel.replace(os.sep, "/")
    try:
        return path.resolve().relative_to(root).as_posix()
    except ValueError:
        return None


def _load_state(root: Path) -> set[tuple]:
    """有向関係 = `from\\tto`（2 要素）、対称関係 = `a\\t関連\\tb`（3 要素）。"""
    fp = root / _STATE_FILE
    if not fp.exists():
        return set()
    try:
        data = json.loads(fp.read_text(encoding="utf-8"))
        out: set[tuple] = set()
        for x in data:
            if not isinstance(x, str):
                continue
            parts = x.split("\t")
            if len(parts) in (2, 3):
                out.add(tuple(parts))
        return out
    except Exception:  # noqa: BLE001
        return set()


def _save_state(root: Path, entries: set[tuple]) -> None:
    fp = root / _STATE_FILE
    payload = sorted("\t".join(r) for r in entries)
    fp.write_text(json.dumps(payload, ensure_ascii=False, indent=0), encoding="utf-8")


def _load_title_state(root: Path) -> dict[str, str]:
    fp = root / _TITLE_STATE_FILE
    if not fp.exists():
        return {}
    try:
        data = json.loads(fp.read_text(encoding="utf-8"))
        return {k: v for k, v in data.items() if isinstance(k, str) and isinstance(v, str)}
    except Exception:  # noqa: BLE001
        return {}


def _save_title_state(root: Path, titles: dict[str, str]) -> None:
    fp = root / _TITLE_STATE_FILE
    fp.write_text(json.dumps(titles, ensure_ascii=False, indent=0, sort_keys=True), encoding="utf-8")


def _tracked_disp(target_id: str, written: str | None, now_title: str,
                   prev_titles: dict[str, str]) -> str:
    """表示名の追従判定。今書かれている表示名(written)が自動生成されたもの
    （＝手で変えていない）なら現タイトルへ追従させる。手で変えたものは残す。

    自動生成とみなすのは次のいずれか:
      - 表示名が無い
      - 表示名が前回 sync 時点の相手タイトルと同じ（＝追従してきただけ）
      - 表示名が相手のファイル名（拡張子なし）と同じ（＝作成時の初期表示）
    最後の条件が大事で、初回 sync の前にタイトルを変えても追従できる
    （前回タイトルの記録が無くても、ファイル名表示は手書きと区別できる）。
    """
    if written is None:
        return now_title
    stem = Path(target_id).stem
    if written == now_title or written == prev_titles.get(target_id) or written == stem:
        return now_title
    return written


# =============================================================================
# 【旧エンジン】 sync_vault 〜（通常は読まない）
#   これは旧 v2 エンジン。`update` / `update_one` / `new` / `retitle_links` は
#   下の simple_sync() を呼ぶ。sync_vault() を呼ぶのは migrate だけ。
#   テストの sync 呼び出しも sync_vault（旧）を叩いている点に注意。
# =============================================================================
def sync_vault(root) -> int:
    """vault 全体を 1 パスで整合させる。見張りコメントを持つノートだけを書き換える。"""
    root = Path(root).resolve()
    by_name = _index(root)

    notes: list[Note] = []
    for p in _iter_md(root):
        try:
            notes.append(parse_note(p))
        except Exception as exc:  # noqa: BLE001
            print(f"note_format_v2: skip {p}: {exc}", file=sys.stderr)

    by_path: dict[Path, Note] = {n.path.resolve(): n for n in notes}

    # インデックスは見出し（### Parent/### BackLink）を持たない。本文のリンクを
    # 子（構造）として扱い、リンク先の Parent に Index が入るようにする。
    for _p, _n in by_path.items():
        if _p.name == "index.md" and not _n.managed:
            _kids = []
            for _ln, _fz in zip(_n.body, _fenced(_n.body)):
                if _fz:
                    continue
                for _m in _link_iter(re.compile(r"\[((?:\\.|[^\]\\])*)\]\(([^)]+)\)"), _ln):
                    _tg = _m.group(2).split("#", 1)[0].strip()
                    if _tg.lower().endswith(".md"):
                        _kids.append((_m.group(1), _tg, None))
            if _kids:
                _n.down["ノート"] = _kids

    ids: dict[Path, str] = {}
    id_to_path: dict[str, Path] = {}
    for k in by_path:
        i = _nid(k, root)
        if i is not None:
            ids[k] = i
            id_to_path[i] = k

    prev_titles = _load_title_state(root)

    def rid(target: str, base: Path) -> str | None:
        tp = _resolve(target, base, root, by_name)
        return ids.get(tp.resolve()) if tp is not None else None

    # 有向関係の同一性は (from_id, to_id) のペア。ラベルは別管理（表示のみ）。
    up_label: dict[tuple[str, str], str] = {}    # (A,B) <- A の こっちにとって 行 `label: [B]`
    down_label: dict[tuple[str, str], str] = {}  # (A,B) <- B の そっちにとって 行 `label: [A]`
    up_ann: dict[tuple[str, str], str] = {}
    up_unresolved: dict[Path, dict[str, list]] = {k: {} for k in by_path}
    body_links: dict[str, set[str]] = {}
    sym_face: dict[tuple[str, frozenset], set[str]] = {}  # (関係, {id,id}) -> 端点

    # `語::` のベース語を集める。対称なので、reciprocal 側の素の `語:` も
    # 対称として扱わないと 2 回目の sync で消えてしまう。`::` は描画で `語:` に
    # 化けて消えるので、前回の状態（3 つ組＝対称）からも引き継ぐ。
    prev_state = _load_state(root)
    dc_labels: set[str] = {r[1] for r in prev_state if len(r) == 3}
    for _n in by_path.values():
        for _d in (_n.up, _n.down):
            for _t in _d:
                if _t.endswith("::"):
                    dc_labels.add(_t[:-2])

    def _sym_label(t: str) -> str | None:
        if t in SYMMETRIC:
            return t
        if t.endswith("::"):
            return t[:-2]
        if t in dc_labels:
            return t
        return None

    for k, n in by_path.items():
        sid = ids.get(k)
        if sid is None:
            continue
        for t, entries in n.up.items():
            if t == _EXTRA:
                continue
            for ti, tg, ann in entries:
                tid = rid(tg, n.path.parent)
                if tid is None:
                    up_unresolved[k].setdefault(t, []).append((ti, tg, ann))
                    continue
                _sym = _sym_label(t)
                if _sym is not None:
                    if tid != sid:
                        sym_face.setdefault((_sym, frozenset((sid, tid))), set()).add(sid)
                    continue
                up_label[(sid, tid)] = t
                if ann:
                    up_ann[(sid, tid)] = ann
        for t, entries in n.down.items():
            if t in _RESERVED:
                continue
            for _ti, tg, _ann in entries:
                src_id = rid(tg, n.path.parent)
                if src_id is None:
                    continue
                _sym = _sym_label(t)
                if _sym is not None:
                    if src_id != sid:
                        sym_face.setdefault((_sym, frozenset((sid, src_id))), set()).add(sid)
                    continue
                down_label[(src_id, sid)] = t
        bl: set[str] = set()
        for tg in _links_in(n.body):
            tid = rid(tg, n.path.parent)
            if tid is not None and tid != sid:
                bl.add(tid)
        body_links[sid] = bl

    prev = prev_state
    prev_pairs = {(a, b) for r in prev if len(r) == 2 for a, b in [r]}
    prev_pairs |= {(r[0], r[2]) for r in prev if len(r) == 3 and _sym_label(r[1]) is None}
    prev_sym = {r for r in prev if len(r) == 3 and _sym_label(r[1]) is not None}

    # --- 有向関係の解決（ペア単位） ---
    present: set[tuple[str, str]] = set()
    for pair in set(up_label) | set(down_label) | prev_pairs:
        up_face = pair in up_label
        down_face = pair in down_label
        if up_face and down_face:
            present.add(pair)
        elif (up_face != down_face) and pair not in prev_pairs:
            present.add(pair)  # 片面だけ & 前回に無い = 今追加
    present = {p for p in present if p[0] in id_to_path and p[1] in id_to_path}

    # --- 対称関係（関連） ---
    present_sym: set[Rel] = set()
    for (t, pair), faces in sym_face.items():
        a, b = sorted(pair)
        if a not in id_to_path or b not in id_to_path:
            continue
        if len(faces) >= 2 or (len(faces) == 1 and (a, t, b) not in prev_sym):
            present_sym.add((a, t, b))

    directed = set(present)
    directed |= {(a, b) for (a, _t, b) in present_sym}
    directed |= {(b, a) for (a, _t, b) in present_sym}

    attr_of: dict[str, str] = {
        i: a for kk, nn in by_path.items()
        if (i := ids.get(kk)) is not None and (a := _fm_attr(nn.fm)) in ATTR_LABELS
    }

    def _mirrored_default(raw: str | None) -> str:
        """相手側が何も書いていない時の既定値（手打ちの `:` / `;` 記法用）。

        相手（source）が `語;`（セミコロン終端）で書いていれば、自動では
        一切ミラーせず素の `ノート`。`語:`（コロン、既定の語も含む）で
        書いていれば、`(語)` の括弧付き（「相手から見た呼び方」の意。
        `ノート` 自体は括弧を付けずそのまま）。何も書かれていなければ
        `ノート`。
        """
        if raw is None:
            return "ノート"
        if raw.endswith(":;"):
            return raw  # `語:;` は相手側も `語:;`（括弧なし・終端）
        if raw.endswith(";"):
            return "ノート"  # `語;` は相手に書かない
        if raw.endswith("::"):
            return raw[:-2] + ":"  # 対称ラベル（両側 `語:`）
        base = raw[:-1] if raw.endswith(":") else raw  # `group:` -> `group`
        return base if base == "ノート" else f"({base})"

    def _is_mirror(lbl: str) -> bool:
        """相手側の自動ミラー表記 `(語)` かどうか。手打ちラベルと区別する。"""
        return len(lbl) >= 2 and lbl.startswith("(") and lbl.endswith(")")

    def up_side_label(pair: tuple[str, str]) -> str:
        """sid 自身の こっちにとって 側を再構築する時のラベル判定。

        - 既に自分で書いている（up_label）ラベルは sticky。ただし `(語)` の
          括弧付き（＝相手側からの自動ミラー）は自分で消しても追従できるよう
          自動扱いにし、相手の現在の書き方に従って更新・削除する。
        - 既定 `ノート` のときに相手が `語:` で書いていればミラーして格上げ。
        - 何も書いていなければ相手の書き方に従う（`_mirrored_default`）。

        例外: sid 自身が attribute（group）を持つ容器ノードの場合は、相手が
        書いた実際の関係名をそのまま使う（§3 の非対称ルールを逆方向にも保つ）。
        """
        sid = pair[0]
        if attr_of.get(sid) in ATTR_LABELS:
            return down_label.get(pair) or "ノート"
        if pair in up_label:
            cur = up_label[pair]
            mirrored = _mirrored_default(down_label.get(pair))
            if _is_mirror(cur):
                # 自動ミラーは相手の現在の書き方に追従（変更・削除も反映）
                return mirrored
            if cur == "ノート" and mirrored != "ノート":
                return mirrored
            return cur
        return _mirrored_default(down_label.get(pair))

    # --- 上側を再構築。相手が attribute 持ちなら自分側はグループ扱い（先頭表示） ---
    # incoming[to] = [from_id]。下側の再構築では `グループ` を特別扱いしない
    # （普通のノートとして扱う）。Child の並びは ユーザーが h/Enter/o/p や
    # 手編集で決めるもので、sync は並べ替えない（sticky）。
    incoming: dict[str, list[str]] = {}
    for (a, b) in present:
        incoming.setdefault(b, []).append(a)

    for k, n in by_path.items():
        sid = ids.get(k)
        if sid is None:
            continue
        # 相手（b）が attribute 持ち（group）でも、こちら側に明示ラベルがあれば
        # それを尊重する。裸（既定ノート）のときだけグループ扱い（先頭の裸リンク）
        # にする ── こうしないと、グループ宛に `aa:` と書いても `(aa)` に
        # ミラーされず、`:` / `;` が効かなくなる。
        def _up_label_for(b: str) -> str:
            lbl = up_side_label((sid, b))
            if b in attr_of and lbl == "ノート":
                return CATEGORY_ATTR
            return lbl

        outgoing = [(b, _up_label_for(b)) for (a, b) in present if a == sid]
        # 既存の並び順と、手で打った表示名を尊重
        order: list[str] = []
        orig_title: dict[str, str] = {}
        for t, es in n.up.items():
            if t == _EXTRA:
                continue
            for _ti, tg, _a in es:
                r = rid(tg, n.path.parent)
                if r:
                    order.append(r)
                    orig_title.setdefault(r, _ti)
        outgoing.sort(key=lambda x: order.index(x[0]) if x[0] in order else 1_000_000)
        new_up: dict[str, list] = {}
        for tid, lbl in outgoing:
            tp = id_to_path[tid]
            tn = by_path.get(tp)
            now_title = tn.title if tn is not None else Path(tid).stem
            disp = _tracked_disp(tid, orig_title.get(tid), now_title, prev_titles)
            new_up.setdefault(lbl, []).append(
                (disp, _rel(n.path.parent, tp), up_ann.get((sid, tid))))
        for t, es in up_unresolved[k].items():
            for e in es:
                new_up.setdefault(t, []).append(e)
        if n.up.get(_EXTRA):
            new_up[_EXTRA] = n.up[_EXTRA]
        n.up = new_up

    # --- 下側を再構築（関係 + 対称 + バックリンク） ---
    for k, n in by_path.items():
        nid = ids.get(k)
        new_down: dict[str, list] = {}
        if nid is not None:
            # 下側（子リスト・バックリンク含む）の表示名は _tracked_disp で判定
            # （書かれている表示名が前回 sync 時点の相手のタイトルと同じなら
            # 現タイトルへ追従、違えば手で変えたとみなしそのまま残す）。
            # ラベルも同様に sticky にする: 既にその相手向けの行があれば、
            # そこに今書かれているラベル（手で変えたものも含む）をそのまま使い
            # 続ける。新規のペアは常に既定の `ノート`（相手側の言葉を勝手に
            # 借りることはしない。関連・カテゴリー属性による強制は対象外）。
            # 表示順も sticky にする: ファイル内で手で並び替えた順序をそのまま
            # 保つ（sync が勝手にソートし直さない）。新規のものだけ末尾に足す。
            orig_down_title: dict[str, str] = {}
            orig_down_label: dict[str, str] = {}
            orig_down_order: list[str] = []
            orig_label_order: list[str] = []
            for t, es in n.down.items():
                if t == _EXTRA:
                    continue
                if t not in orig_label_order:
                    orig_label_order.append(t)
                for _ti, tg, _ann in es:
                    r = rid(tg, n.path.parent)
                    if r:
                        orig_down_title.setdefault(r, _ti)
                        orig_down_label.setdefault(r, t)
                        if r not in orig_down_order:
                            orig_down_order.append(r)

            def _down_sort_key(s: str) -> int:
                return orig_down_order.index(s) if s in orig_down_order else 1_000_000

            by_lbl: dict[str, list[str]] = {}
            for a in incoming.get(nid, []):
                if (nid, a) in present:  # 相互は下側に出さない
                    continue
                src_up = up_label.get((a, nid))       # 相手（a）側のラベル
                src_down = down_label.get((a, nid))   # 自分側のラベル
                src_raw = src_up or src_down
                # 下側（Child）では `グループ` を普通のノートとして扱う。
                # 位置をガチガチに固定するのは Parent（上側）の表示だけ。
                if src_up is not None and src_up.endswith(":;"):
                    # 相手（a）が `語:;` … こちら側も `語:;`（括弧なし・終端）
                    lbl = src_up
                elif src_up is not None and src_up.endswith(";"):
                    # 相手（a）が `語;` = 「このラベルは相手側に見せない」の意。
                    # 既に自動ミラーで入った行が残っていても既定の『ノート』へ戻す。
                    lbl = "ノート"
                elif a in orig_down_label:
                    cur = orig_down_label[a]
                    m = _mirrored_default(src_raw)
                    if _is_mirror(cur):
                        lbl = m  # 自動ミラー `(語)` は相手の変更・削除に追従
                    elif cur == "ノート" and m != "ノート":
                        lbl = m  # 既定の裸リンクは相手が `語:` なら自動ミラーへ格上げ
                    else:
                        lbl = cur  # 手で書いたラベルは sticky（`語;` もそのまま残す）
                elif attr_of.get(nid) in ATTR_LABELS:
                    # §3 の例外: 容器ノード自身の そっちにとって には、実際に
                    # 選んだ関係名がそのまま並ぶ（ノート の既定値に落とさない）。
                    lbl = src_raw or "ノート"
                else:
                    lbl = _mirrored_default(src_raw)
                if lbl.rstrip(";") == CATEGORY_ATTR:
                    lbl = "ノート"  # 下側では グループ を普通のノートとして扱う
                by_lbl.setdefault(lbl, []).append(a)
            for (a, t, b) in present_sym:
                other = b if a == nid else (a if b == nid else None)
                if other is not None:
                    by_lbl.setdefault(t, []).append(other)
            # Child の並びは基本 sticky（既存ラベルはファイル内の元の順、新規は
            # 末尾）。`グループ` は下側では普通のノートに正規化済みなので、
            # 既定リンクは 1 つの裸ブロックにまとまり、ユーザーが決めた並びのまま
            # 保たれる。sync は並べ替えない（位置は h/Enter/o/p と手編集で決める）。
            ordered_lbls = [l for l in orig_label_order if l in by_lbl]
            ordered_lbls += [l for l in by_lbl if l not in orig_label_order]
            for lbl in ordered_lbls:
                srcs = by_lbl[lbl]
                new_down[lbl] = [
                    (_tracked_disp(s, orig_down_title.get(s), by_path[id_to_path[s]].title,
                                   prev_titles),
                     _rel(n.path.parent, id_to_path[s]), None)
                    for s in sorted(set(srcs), key=_down_sort_key)
                ]
            back = sorted(
                (s for s, targets in body_links.items()
                 if nid in targets and (s, nid) not in directed
                 and (nid, s) not in directed and s in id_to_path),
                key=_down_sort_key,
            )
            if back:
                new_down[BACKLINK] = [
                    (_tracked_disp(s, orig_down_title.get(s), by_path[id_to_path[s]].title,
                                   prev_titles),
                     _rel(n.path.parent, id_to_path[s]), None)
                    for s in back
                ]
        if n.down.get(_EXTRA):
            new_down[_EXTRA] = n.down[_EXTRA]
        n.down = new_down
        if nid is not None:
            n.down_rendered = _render_down_preserving(
                n, lambda tg, base=n.path.parent: rid(tg, base))

    _save_state(root, set(present) | present_sym)
    _save_title_state(root, {i: by_path[p].title for i, p in id_to_path.items()})

    changed = 0
    for n in notes:
        if not n.managed:  # 外部ファイル（日記など）は絶対に書き換えない
            continue
        new_text = render_note(n)
        if new_text != n.path.read_text(encoding="utf-8"):
            n.path.write_text(new_text, encoding="utf-8")
            changed += 1
    return changed


# ---------------------------------------------------------------------------
# simple sync: 本文リンク = 子（outgoing）。Parent = 手書き ＋ Index/グループ（sync 管理）。
#   BackLink = incoming − Parent − 自分の outgoing。
#   `### Related` は zr が両ノートに相互に書く対称セクション。sync は
#   表示名の追従・消えたファイルの掃除・対称性の維持（片側だけのペアを外す）
#   だけを行い、リンクの追加はしない。incoming へも反映しない。
# ---------------------------------------------------------------------------

_SIMPLE_INLINE_LINK = re.compile(r"\[((?:\\.|[^\]\\])*)\]\(([^)]+)\)")
# 行全体がリンク 1 本だけの行（前後の空白は許す）
_SIMPLE_LINK_LINE_RE = re.compile(r"^\s*(\[(?:\\.|[^\]\\])*\]\([^)]+\))\s*(?:—\s*\S+)?\s*$")


def _link_target(link_line: str) -> str:
    """リンク行からターゲットを取り出す。"""
    m = _SIMPLE_INLINE_LINK.search(link_line)
    return m.group(2).split("#", 1)[0].strip() if m else ""


def _links_from(lines: list[str]) -> list[tuple[str, str]]:
    out: list[tuple[str, str]] = []
    for ln, fz in zip(lines, _fenced(lines)):
        if fz:
            continue
        for m in _link_iter(_SIMPLE_INLINE_LINK, ln):
            tg = m.group(2).split("#", 1)[0].strip()
            if tg.lower().endswith(".md"):
                out.append((m.group(1), tg))
    return out


def _used_display_names(notes: dict, incoming: dict | None = None) -> set[str]:
    """vault 内のリンクが実際に使っている表示名を集める。

    対象は本文・Parent・Related のリンクの表示名だけ。自動生成される BackLink の
    表示名（＝相手の title）は数えない。BackLink 行は `\\S` で動かさないので、その
    ための yomi は不要で、数えてしまうと存在しない表示名の yomi が残り続ける。
    `incoming` は互換のため受けるが使わない。
    """
    used: set[str] = set()
    for n in notes.values():
        for kind in ("body", "parent", "ctx", "related", "pbranch", "cbranch"):
            for disp, _tg in _links_from(n.get(kind, [])):
                if disp:
                    used.add(disp)
    return used


PRUNE_EVERY = 600   # 秒。よみの JSON の掃除は、保存のたびではなく、これだけ間をあけて行う（全部の殻を読むので）


def _yomi_to_store(root: Path, notes: dict) -> int:
    """ノートの front matter に残っている古い yomi: を、vault の .gnosis/yomi/ の JSON に移す。移したノート数。"""
    root = Path(root)
    store = None
    moved = 0
    for p, n in notes.items():
        if not n["fm"]:
            continue
        mapping = parse_yomi_map(n["fm"])
        if not mapping:
            continue
        if store is None:
            store = _jy.YomiStore(root)
        try:
            nid = p.resolve().relative_to(root.resolve()).as_posix()
        except ValueError:
            continue
        store.import_map(nid, mapping)
        n["fm"] = set_yomi_map(n["fm"], {})
        moved += 1
    return moved


def _prune_yomi_store(root: Path, notes: dict, used: set[str]) -> int:
    """JSON のよみのうち、使われていない表示名・無くなったノートの分を消す（間をあけて行う）。"""
    root = Path(root)
    d = root / ".gnosis" / "yomi"
    if not d.is_dir():
        return 0
    stamp = d / ".pruned"
    try:
        import time
        if time.time() - stamp.stat().st_mtime < PRUNE_EVERY:
            return 0
    except OSError:
        pass
    rr = root.resolve()
    existing = set()
    for p in notes:
        try:
            existing.add(p.resolve().relative_to(rr).as_posix())
        except ValueError:
            pass
    n = _jy.YomiStore(root).prune(used, existing)
    try:
        stamp.write_text("", encoding="utf-8")
    except OSError:
        pass
    return n


def _prune_yomi_maps(notes: dict, used: set[str]) -> int:
    """使われていない表示名の yomi を各ノートの front matter から取り除く。

    使用中の表示名（リンクの表示名、および incoming のあるノートの title）だけ残す。
    front matter を書き換えたノート数を返す。
    """
    changed = 0
    for n in notes.values():
        if not n["fm"]:
            continue
        mapping = parse_yomi_map(n["fm"])
        if not mapping:
            continue
        keep = {k: v for k, v in mapping.items() if k in used}
        if len(keep) != len(mapping):
            n["fm"] = set_yomi_map(n["fm"], keep)
            changed += 1
    return changed


def _content_hash(text: str) -> str:
    return hashlib.blake2b(text.encode("utf-8"), digest_size=8).hexdigest()


def _simple_parse(path: Path) -> dict:
    return _simple_parse_text(path, path.read_text(encoding="utf-8"))


def _take_branch_group_block(lines: list[str]) -> tuple[list[str], list[str], bool]:
    """BranchGroup（旧 ThisNoteGroup）の直下にあるリンクだけを抜き出す。

    コードブロック中の同名文字列や、それ以降の自由本文はそのまま保つ。
    """
    flags = _fenced(lines)
    for i, ln in enumerate(lines):
        if flags[i] or ln.strip() not in (BRANCH_GROUP_HEAD, LEGACY_THIS_NOTE_GROUP_HEAD):
            continue
        j = i + 1
        links: list[str] = []
        while j < len(lines) and _SIMPLE_LINK_LINE_RE.match(lines[j]):
            links.append(lines[j].lstrip(" "))  # 段は付けない（並びだけ。昔の段つきの行も sync で段なしに戻る）
            j += 1
        if j < len(lines) and not lines[j].strip():
            j += 1  # 区切りの空行は 1 行だけ（それ以上は本文の余白として残す）
        return links, lines[:i] + lines[j:], True
    return [], lines, False


def _take_parent_branch_block(lines: list[str]) -> tuple[list[str], list[str]]:
    """`ParentBranch:`（本文の上の先頭のブロック）を読む。範囲は見出しの直後に続くリンク行だけ。
    旧形式の `### ParentBranch`（本文の下の節）はここでは読まない（節として読む）。"""
    flags = _fenced(lines)
    for i, ln in enumerate(lines):
        if flags[i] or ln.strip() != PARENT_BRANCH_MARK:
            continue
        j = i + 1
        while j < len(lines) and _SIMPLE_LINK_LINE_RE.match(lines[j]):
            j += 1
        links = lines[i + 1:j]
        if j < len(lines) and not lines[j].strip():
            j += 1  # 区切りの空行は 1 行だけ（それ以上は本文の余白として残す）
        return links, lines[:i] + lines[j:]
    return [], lines


def _take_group_block(lines: list[str]) -> tuple[list[str], list[str]]:
    """新しい Group: と旧 ### Group を読む。

    Group: は「このノートが属するグループ」の一覧。範囲は、見出しの直後に**続けて**並ぶリンク行だけ
    （空行・文章・別の見出しで終わる）。空行より後ろのリンクは本文で、Group: には入れない。
    本文の中でリンクされた相手は、相手がグループなら「その本文に自分がある」ので、同期が Group: を足す
    （グループの Group: に書かれた相手は、そのグループの親であって、メンバーではない）。
    旧 `### Group`（末尾の節）だけは、従来どおり次の見出しまでの空行つきのリンク群を読む。
    単独リンク・区切り空行以外の本文は残す（移行時に失わない）。
    """
    flags = _fenced(lines)
    for i, ln in enumerate(lines):
        if flags[i] or ln.strip() not in (GROUP_MARK, LEGACY_GROUP_MARK):
            continue
        j = i + 1
        if ln.strip() == LEGACY_GROUP_MARK:
            while j < len(lines) and (not lines[j].strip() or _SIMPLE_LINK_LINE_RE.match(lines[j])):
                j += 1
            return lines[i + 1:j], lines[:i] + lines[j:]
        while j < len(lines) and _SIMPLE_LINK_LINE_RE.match(lines[j]):
            j += 1
        links = lines[i + 1:j]
        # ブロックと本文のあいだの区切りの空行は 1 行だけ取り除く（書き戻しが 1 行作り直す）。
        # それ以上の空行は利用者が本文のために空けた余白なので、本文として残す。
        if j < len(lines) and not lines[j].strip():
            j += 1
        return links, lines[:i] + lines[j:]
    return [], lines


def _simple_parse_text(path: Path, text: str) -> dict:
    # 末尾の改行で生じる空要素は本文に入れない（残すと `### Parent` の上に空行が増える）。
    # `### Parent` より前の空行（本文の途中の余白）は残る。
    fm, rest = _split_front_matter(text.rstrip("\n").split("\n"))
    title = _title_of(fm, rest, path.stem)
    # Group / BranchGroup の後ろに Context がある形式でも、先頭のブロックを
    # 順に取り除いてから Context を読む。旧 ThisNoteGroup も受け付ける。
    # 先頭のブロック（ParentBranch: / BranchGroup: / Group:）は、ファイルで先に現れるものから順に取る。
    # 後ろのブロックを先に取ると、その下の区切りの空行を一緒に外してしまい、本文のリンク行が
    # 上のブロックに吸い込まれる（並びは BranchGroup → Group → ParentBranch だが、古い並びのノートも読む）。
    def _first_at(heads):
        return next((i for i, ln in enumerate(rest) if ln.strip() in heads), len(rest) + 1)
    order = sorted([(_first_at((PARENT_BRANCH_MARK,)), "pb"),
                    (_first_at((BRANCH_GROUP_HEAD, LEGACY_THIS_NOTE_GROUP_HEAD)), "bg"),
                    (_first_at((GROUP_MARK, LEGACY_GROUP_MARK)), "gp")])
    pb_block: list[str] = []
    group_block: list[str] = []
    branch_links: list[str] = []
    has_branch_group = False
    for _at, kind in order:
        if kind == "pb":
            pb_block, rest = _take_parent_branch_block(rest)
        elif kind == "bg":
            branch_links, rest, has_branch_group = _take_branch_group_block(rest)
        else:
            group_block, rest = _take_group_block(rest)
    ctx: list[str] = []
    ctx_at = -1
    blk = find_context_block(rest)
    if blk:
        ctx = rest[blk[0] + 1:blk[1] + 1]
        ctx_at = blk[0]
        end = blk[1] + 1
        if end < len(rest) and not rest[end].strip():
            end += 1  # ブロックと本文のあいだの区切りの空行は 1 行だけ取り除く（余白はそのまま残す）
        rest = rest[:blk[0]] + rest[end:]
    sec: dict[str, list[str]] = {k: [] for k in ("body", "parent", "group", "related", "back",
                                                  "pbranch", "cbranch")}
    heads = {CONTEXT_MARK: "parent", UP_MARK: "parent",  # UP_MARK = 旧 `### Parent`
             RELATED_MARK: "related", RELATED_MARK_LEGACY: "related",
             BACKLINK_MARK: "back", BACKLINK_MARK_LEGACY: "back",
             PARENT_BRANCH_MARK_LEGACY: "pbranch",
             CHILD_BRANCH_MARK: "cbranch", CHILD_BRANCH_MARK_LEGACY: "cbranch"}
    cur = "body"
    for ln, fz in zip(rest, _fenced(rest)):
        if fz:  # コードブロックの中は見出し・リンクとして扱わない
            sec[cur].append(ln)
            continue
        s = ln.strip()
        if s in heads:
            cur = heads[s]
            continue
        sec[cur].append(ln)
    # キャッシュ形式を変えず、BranchGroup は正規化された本文の一部として保存する。
    # 書き戻し時に必ず H1 の直後へ移す。
    if has_branch_group:
        sec["body"] += [BRANCH_GROUP_HEAD] + branch_links
    # 関係の節がまったく無いノートは、末尾の空行（新しいノートの書き出し用の余白）を残す
    tail_blanks = 0 if cur != "body" else max(0, len(text) - len(text.rstrip("\n")) - 1)
    return {"fm": fm, "title": title, "body": sec["body"], "parent": sec["parent"],
            "group": group_block + sec["group"], "related": sec["related"], "back": sec["back"],
            "pbranch": pb_block + sec["pbranch"], "cbranch": sec["cbranch"], "ctx": ctx, "ctx_at": ctx_at,
            "tail_blanks": tail_blanks, "hash": _content_hash(text)}


# パース結果の差分キャッシュ。`update` は保存のたびに vault 全体を走査するので、
# 内容が変わっていないファイルは前回のパース結果を使い回す。鮮度は mtime では
# なく内容ハッシュ（blake2b 8byte）で判定する。mtime+size だと、粗い時刻刻みの
# ファイルシステムや同サイズの編集（OldTitle→NewTitle 等）を取りこぼすため。
# 壊れていても例外を握って全件パースに落ちるだけ。
_PARSE_CACHE_FILE = ".pkm_parse_cache_v2.json"


def _load_parse_cache(root: Path) -> dict:
    fp = root / _PARSE_CACHE_FILE
    if not fp.exists():
        return {}
    try:
        data = json.loads(fp.read_text(encoding="utf-8"))
        return data if isinstance(data, dict) else {}
    except Exception:  # noqa: BLE001
        return {}


def _save_parse_cache(root: Path, cache: dict) -> None:
    fp = root / _PARSE_CACHE_FILE
    try:
        tmp = fp.with_name(fp.name + ".tmp")
        tmp.write_text(json.dumps(cache, ensure_ascii=False, separators=(",", ":")),
                       encoding="utf-8")
        os.replace(tmp, fp)
    except OSError:
        pass


_GROUP_STATE_FILE = ".pkm_group_state_v1.json"


def _load_group_state(root: Path) -> dict:
    """前回の sync が書き終えた（ファイルの内容が最終形と一致した）時点の Group のリンク行。

    parse キャッシュの group は書く前の解析結果で、sync が自動で足した所属を含まない。
    利用者が Group: からリンクを消したことを見分けるには、「ファイルに実際にあった最終形」が要る。
    """
    fp = root / _GROUP_STATE_FILE
    try:
        data = json.loads(fp.read_text(encoding="utf-8"))
        return data if isinstance(data, dict) else {}
    except Exception:  # noqa: BLE001
        return {}


def _save_group_state(root: Path, state: dict) -> None:
    fp = root / _GROUP_STATE_FILE
    try:
        tmp = fp.with_name(fp.name + ".tmp")
        tmp.write_text(json.dumps(state, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
        os.replace(tmp, fp)
    except OSError:
        pass


_BRANCH_STATE_FILE = ".pkm_branch_state_v1.json"


def _load_branch_pairs(root: Path) -> set[str]:
    """前回の sync の終わりに、親の ChildBranch: と子の ParentBranch: の両方がそろっていた組（"親\t子"）。
    子の ParentBranch: を手で消したことを見分けるのに使う（そろっていた組が片側だけになっていたら、消したと判断する）。"""
    try:
        data = json.loads((root / _BRANCH_STATE_FILE).read_text(encoding="utf-8"))
        return set(data) if isinstance(data, list) else set()
    except Exception:  # noqa: BLE001
        return set()


def _save_branch_pairs(root: Path, pairs: set[str]) -> None:
    fp = root / _BRANCH_STATE_FILE
    try:
        tmp = fp.with_name(fp.name + ".tmp")
        tmp.write_text(json.dumps(sorted(pairs), ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
        os.replace(tmp, fp)
    except OSError:
        pass


def _update_body_link_names(body: list[str], path: Path, resolver, titles: dict,
                            prev_titles: dict | None = None) -> list[str]:
    """本文リンクの表示名を、リンク先の現在のタイトルに追従させる。

    追従させる（＝自動生成とみなす）のは次のいずれか。手書き名は残す。
      - 表示名がリンク先の現在のタイトルと同じ
      - 表示名が前回 sync 時点のリンク先タイトルと同じ（＝追従してきただけ）
      - 表示名がリンク先のファイル名（拡張子なし）と同じ（＝作成時の初期表示）
    前回タイトルを照合しないと、タイトル変更後に「旧タイトル表示のまま」の
    リンクを手書き名と誤判定して更新しない（simple_sync の retitle 不具合）。
    """
    prev_titles = prev_titles or {}
    base_dir = path.parent

    def repl(m):
        disp, tg = m.group(1), m.group(2)
        base = tg.split("#", 1)[0].strip()
        if not base.lower().endswith(".md"):
            return m.group(0)
        rp = resolver(base, base_dir)
        if rp is None or rp not in titles:
            return m.group(0)
        now = titles[rp]
        if disp == now or disp == prev_titles.get(rp) or disp == Path(base).stem:
            return f"[{now}]({tg})"
        return m.group(0)
    out: list[str] = []
    for ln, fz in zip(body, _fenced(body)):
        out.append(ln if fz else _link_sub(_SIMPLE_INLINE_LINK, repl, ln))
    return out


def _heading_labels(body: list[str]) -> dict[str, str]:
    """Resolve zo/GitHub fragment slugs to their visible Markdown headings."""
    seen: dict[str, int] = {}
    out: dict[str, str] = {}
    for line, fenced in zip(body, _fenced(body)):
        if fenced:
            continue
        match = re.match(r"^\s*#{1,6}\s+(.+?)\s*#*\s*$", line)
        if not match:
            continue
        heading = match.group(1).strip()
        # GitHub-compatible basic slug rules, matching zo's heading picker:
        # lowercase, keep Unicode letters and numbers, remove punctuation,
        # replace whitespace with hyphens, and suffix duplicate headings.
        plain = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", heading).lower()
        slug = re.sub(r"[^\w\s-]", "", plain)
        slug = re.sub(r"\s", "-", slug)
        next_num = seen.get(slug, 0)
        unique = slug if next_num == 0 else f"{slug}-{next_num}"
        while unique in out:
            next_num += 1
            unique = f"{slug}-{next_num}"
        seen[slug] = next_num + 1
        out[unique] = heading
    return out


def _preserve_parent(existing: list[str], path: Path, resolver, titles: dict,
                     heading_labels: dict | None = None) -> list[str]:
    """Keep typed links but follow current title and preserve zo outline labels.

    In a Context/ParentBranch/Group link, title normalization used to erase the
    visible #heading while leaving #slug in the URL. Restore the actual heading,
    without changing the target, and handle the same pre-existing broken links.
    """
    out: list[str] = []
    base_dir = path.parent
    for ln in existing:
        m = _SIMPLE_INLINE_LINK.search(ln)
        if m:
            target = m.group(2)
            tg, sep, frag = target.partition("#")
            rp = resolver(tg.strip(), base_dir)
            if rp is not None and rp in titles:
                display = titles[rp]
                if sep and frag:
                    headings = (heading_labels or {}).get(rp, {})
                    label = headings.get(unquote(frag), "")
                    if not label:
                        # Preserve an already displayed human-readable heading
                        # even when the target note has since been edited.
                        label = m.group(1).partition("#")[2] or unquote(frag).replace("-", " ")
                    display += "#" + label
                out.append(f"[{display}]({target})")
            else:
                out.append(ln)
        else:
            out.append(ln)
    return out


def _separate_parent_groups(lines: list[str], kind_of) -> list[str]:
    """Parent の並び規則: グループのリンク行は上、普通のノートのリンク行は下。

    - 分離だけを強制する。文字・空行・並び替えは自由に残る（リンク以外の行は動かさない）。
    - グループの行が最初のノートの行より下にあれば、グループの塊の末尾へ引き上げる
      （グループが無ければ最初のノートの行の位置へ）。引き上げる順序は元のまま。
    - 最後のグループの行と最初のノートの行の間に空行が 1 つも無ければ 1 つ入れる。
    - どちらかが無いときは何もしない。

    kind_of(行) は、グループへのリンク行なら True、普通のノートへのリンク行なら False、
    それ以外（文字・空行・ノート以外へのリンク）なら None を返す。冪等。
    """
    kinds = [kind_of(ln) for ln in lines]
    g_idx = [i for i, k in enumerate(kinds) if k is True]
    n_idx = [i for i, k in enumerate(kinds) if k is False]
    if not g_idx or not n_idx:
        return lines
    out = list(lines)
    first_n = n_idx[0]
    stray = [i for i in g_idx if i > first_n]
    if stray:
        moved = [out[i] for i in stray]
        for i in reversed(stray):
            del out[i]
        before = [i for i in g_idx if i < first_n]
        at = before[-1] + 1 if before else first_n
        out[at:at] = moved
    kinds = [kind_of(ln) for ln in out]
    last_g = max(i for i, k in enumerate(kinds) if k is True)
    first_n = min(i for i, k in enumerate(kinds) if k is False)
    if not any(ln.strip() == "" for ln in out[last_g + 1:first_n]):
        out.insert(first_n, "")
    return out


def _tidy_blanks(lines: list[str]) -> list[str]:
    """先頭・末尾の空行を落とし、連続する空行を 1 つにする（仕分けで動かしたあとの整形）。"""
    out: list[str] = []
    for ln in lines:
        if ln.strip() == "" and (not out or out[-1].strip() == ""):
            continue
        out.append(ln)
    while out and out[-1].strip() == "":
        out.pop()
    return out


def _prune_dangling(lines: list[str], path: Path, resolver) -> list[str]:
    """存在しない .md へのリンクを掃除する（消えたファイルの残骸を消す）。

    - 行全体がリンク 1 本だけの行 → 行ごと取り除く。
    - 文中に埋もれたリンク → リンク記法だけ外して表示名の文字は残す
      （文章を消さない）。`![alt](pic.png)` 等の .md 以外は触らない。
    """
    out: list[str] = []
    base_dir = path.parent
    for ln, fz in zip(lines, _fenced(lines)):
        if fz:
            out.append(ln)
            continue
        if _SIMPLE_LINK_LINE_RE.match(ln):
            tg = _link_target(ln)
            if tg.lower().endswith(".md") and resolver(tg, base_dir) is None:
                continue
            out.append(ln)
            continue

        def repl(m):
            disp, tg = m.group(1), m.group(2)
            base = tg.split("#", 1)[0].strip()
            if base.lower().endswith(".md") and resolver(base, base_dir) is None:
                return disp
            return m.group(0)

        out.append(_link_sub(_SIMPLE_INLINE_LINK, repl, ln))
    return out


def _prune_one_sided_related(lines: list[str], path: Path, resolver,
                             related_t: dict) -> list[str]:
    """対称でない Related リンク（相手側の Related に自分が無い）を掃除する。

    Related は両側に同じ相手があるときだけ成立する（zr は両側に書く）。
    片側で消されたら、次回 sync でもう片側からも消える。
    行の扱いは `_prune_dangling` と同じ（リンク単独行は行ごと、
    文中リンクは表示名の文字だけ残す）。
    """
    base_dir = path.parent

    def one_sided(tg: str) -> bool:
        rp = resolver(tg, base_dir)
        return rp is None or rp == path or path not in related_t.get(rp, set())

    out: list[str] = []
    for ln, fz in zip(lines, _fenced(lines)):
        if fz:
            out.append(ln)
            continue
        if _SIMPLE_LINK_LINE_RE.match(ln):
            tg = _link_target(ln)
            if tg.lower().endswith(".md") and one_sided(tg):
                continue
            out.append(ln)
            continue

        def repl(m):
            disp, tg = m.group(1), m.group(2)
            base = tg.split("#", 1)[0].strip()
            if base.lower().endswith(".md") and one_sided(base):
                return disp
            return m.group(0)

        out.append(_link_sub(_SIMPLE_INLINE_LINK, repl, ln))
    return out


def _rstrip_blank(lines: list[str]) -> list[str]:
    k = len(lines)
    while k > 0 and not lines[k - 1].strip():
        k -= 1
    return lines[:k]


# BackLink 見出しを出さない生成ノート（紙PKM の Folgezettel-Index。ファイル名はふつうのタイムスタンプ名なので、題で見分ける）
_NO_BACKLINK_TITLES = ("Folgezettel-Index",)


def _ends_in_label_block(lines: list[str]) -> bool:
    """末尾のリンク行の連なりが、`Group:` のような見出し行（末尾が `:`）の下にあるか（ブロックの一部か）。"""
    i = len(lines) - 1
    while i >= 0 and _SIMPLE_LINK_LINE_RE.match(lines[i]):
        i -= 1
    return i >= 0 and bool(re.match(r"^[^\s\[\]()]+:\s*$", lines[i]))


def _body_with_context(n: dict, links: list[str], enabled: bool,
                       group_lines: list[str] | None = None) -> list[str]:
    """本文冒頭のブロックを BranchGroup: → Group: → ParentBranch: → Context: の順で出力する（2026-10-20 に変更）。

    BranchGroup は直接のブランチで派生したグループ（旧 ThisNoteGroup）。
    Group は所属（手動＋自動）、Context は文脈。
    """
    body = list(n["body"])
    links = [ln for ln in links if ln.strip()]
    groups = [ln for ln in (group_lines or []) if ln.strip()]

    # BranchGroup と旧 ThisNoteGroup を回収して先頭へ正規化する。
    branch_links, body, found_branch_group = _take_branch_group_block(body)

    blocks: list[str] = []
    pbranch = [ln for ln in (n.get("pbranch") or []) if ln.strip()]
    if found_branch_group:
        blocks += [BRANCH_GROUP_HEAD] + branch_links
    if groups:
        blocks += [GROUP_MARK] + groups
    if pbranch:
        blocks += [PARENT_BRANCH_MARK] + pbranch
    if links:
        blocks += [CONTEXT_HEAD] + links
    if not blocks:
        # Context ブロックが空になった際、その位置に残る余分な空行 1 つだけを除く。
        # 新規ノートの入力用余白は減らさない。
        at = n.get("ctx_at", -1)
        if 0 <= at < len(body) and at > 0 and not body[at].strip() and not body[at - 1].strip():
            del body[at]
        return body

    flags = _fenced(body)
    h1 = next((i for i, ln in enumerate(body)
               if not flags[i] and re.match(r"^#\s+\S", ln)), None)
    pos = h1 + 1 if h1 is not None else 0
    # H1 とブロックのあいだの空行は 1 行に整える。ブロックの下の余白（利用者が本文のために空けた空行）は、
    # 区切りの 1 行を除いてそのまま残す。本文自体やリンクを移動・削除しない。
    if pos < len(body) and not body[pos].strip():
        del body[pos]
    body[pos:pos] = ([""] if pos else []) + blocks + [""]
    return body

def _split_child_branch(cbranch: list[str], body: list[str], base: Path | None = None,
                        ctx_kids: set | None = None, pb_kids: set | None = None,
                        titles: dict | None = None, timeline: bool = False, stale: set | None = None,
                        moved: list[str] | None = None, numbers: dict | None = None) -> list[str]:
    """All explicitly declared children, including links repeated in the body.

    Every child's ParentBranch pointing to this parent is authoritative, apart
    from children already displayed in BranchGroup. Merely mentioning a note in
    prose does not make it a child. Sort by Folgezettel number.
    """
    import folgezettel as fz

    def resolve_link(tg: str) -> Path | None:
        if base is None:
            return None
        raw = tg.split("#", 1)[0].strip()
        for cand in (raw, unquote(raw)):
            try:
                q = (base.parent / cand).resolve()
            except (OSError, ValueError):
                continue
            if q.exists():
                return q
        return None

    # BranchGroup contains the structural group children already. Do not
    # duplicate those links in ChildBranch, even when a child ParentBranch
    # points back here or an old ChildBranch entry already exists.
    branch_lines, _unused, _kind = _take_branch_group_block(body)
    branch_group_children = {
        target
        for _display, raw in _links_from(branch_lines)
        for target in [resolve_link(raw)]
        if target is not None
    }
    entries: list[tuple[str, Path | None]] = []
    listed: set[Path] = set()

    def include(ln: str):
        targets = [resolve_link(tg) for _d, tg in _links_from([ln])]
        targets = [t for t in targets if t is not None]
        if targets:
            # A single declared child is written exactly once, regardless of
            # duplicate ChildBranch lines or its appearances in the body.
            for t in targets:
                if t not in listed and t not in (stale or set()) and t not in branch_group_children:
                    entries.append((ln, t))
                    listed.add(t)
        elif ln.strip() and not _links_from([ln]):
            entries.append((ln, None))

    for ln in cbranch:
        include(ln)
    # Timeline's body-only child rows were already moved to ChildBranch.
    for ln in moved or []:
        include(ln)
    for child in pb_kids or set():
        if base is None or child in listed or child in (stale or set()) or child in branch_group_children:
            continue
        title = (titles or {}).get(child) or child.stem
        link = f"[{title}]({os.path.relpath(str(child), str(base.parent))})"
        entries.append((link, child))
        listed.add(child)

    def order(item):
        ln, target = item
        ident = (numbers or {}).get(target, "") if target is not None else ""
        if ident and fz.ID_RE.fullmatch(ident):
            return (0, fz.natural_key(ident), str(target))
        title = (titles or {}).get(target, "") if target is not None else ""
        return (1, (title or ln).casefold(), str(target or ""))

    entries.sort(key=order)
    return [ln for ln, _target in entries]


_YAML_TITLE_LINE = re.compile(r"^\s*title\s*:")


def _drop_yaml_title(n: dict) -> dict:
    """front matter の title: を消す（題は先頭の # 見出し）。H1 が無いノートは、title: の題を H1 として本文の先頭に入れる。"""
    if not any(_YAML_TITLE_LINE.match(ln) for ln in n["fm"]):
        return n
    n = dict(n)
    n["fm"] = [ln for ln in n["fm"] if not _YAML_TITLE_LINE.match(ln)]
    body = list(n.get("body") or [])
    if not any(not fz and re.match(r"^#\s+\S", ln) for ln, fz in zip(body, _fenced(body))):
        n["body"] = ["# " + n["title"], ""] + body
    return n


def _simple_render(name: str, n: dict, path: Path, parent_lines: list[str], back: list[Path], titles: dict,
                   group_lines: list[str] | None = None) -> str:
    """関係の節（### Context / Group / Related / BackLink）は、中身があるものだけ書く。
    中身が空の節は見出しごと出さない（新しいノートは本文だけ）。"""
    n = _drop_yaml_title(n)
    is_timeline = any(re.match(r"^\s*timeline\s*:\s*true\s*$", ln, re.I) for ln in n["fm"])
    moved_kids: list[str] = []
    if is_timeline:
        # 本文にある「子へのリンクだけの行」は ChildBranch: へ移す（本文と二重にしない）
        n = dict(n)
        body = list(n.get("body") or [])
        keep = []
        for ln, fz in zip(body, _fenced(body)):
            if not fz and re.match(r"^\[[^\]]*\]\([^)\s]+\.md\)\s*$", ln):
                moved_kids.append(ln.strip())
            else:
                keep.append(ln)
        if moved_kids:
            n["body"] = keep
    lines = list(n["fm"])
    if lines == ["---", "---"]:
        lines = []   # 中身の無い front matter は書かない（題は先頭の # 見出し）
    # Context は本文の冒頭（H1 の直後）の `Context:` ブロック。新形式のノート（既にブロックがある・旧節が無い）はこれ。
    # 旧形式の `### Context` 節だけのノートは、勝手に移行せず旧形式のまま書く。
    use_block = n.get("ctx_at", -1) >= 0 or not n["parent"]
    if name == "index.md":
        lines += _body_with_context(n, n.get("ctx", []), True)
        while lines and lines[-1].strip() == "":
            lines.pop()
        return "\n".join(lines) + "\n"
    lines += _body_with_context(n, parent_lines if use_block else [], True, group_lines)

    def _has(ls) -> bool:
        return bool(ls) and any(ln.strip() for ln in ls)

    related = [ln for ln in n.get("related", [])]
    back_lines = [f"[{titles[t]}]({_rel(path.parent, t)})" for t in back] if n.get('title') not in _NO_BACKLINK_TITLES else []
    sections: list[tuple[str, list[str]]] = []
    # 本文の下の節の並びは ChildBranch → Related → BackLink（ParentBranch は本文の上の先頭のブロック）
    if not use_block and _has(parent_lines):
        sections.append((CONTEXT_MARK, parent_lines))
    elif use_block and _has(n.get("_leftover")):
        sections.append((CONTEXT_MARK, n["_leftover"]))  # 旧節にあったリンク以外の行（メモなど）は失わない
    cbranch = _split_child_branch(n.get("cbranch") or [], n.get("body") or [], path, n.get("_ctx_kids"),
                                  n.get("_pb_kids"), titles, stale=n.get("_stale_kids"),
                                  timeline=is_timeline, moved=moved_kids,
                                  numbers=n.get("_child_numbers"))
    if _has(cbranch):
        sections.append((CHILD_BRANCH_MARK, cbranch))
    # `### Related` は zr で足したときだけ存在する（sync が勝手に作らない）。
    if _has(related):
        sections.append((RELATED_MARK, related))
    if back_lines:
        sections.append((BACKLINK_MARK, back_lines))
    if not sections:
        # 節が無いノートは、末尾の空行（書き出しの余白）をそのまま残す。上のブロックだけのノート（zk のグループなど）は
        # ブロックの下の区切りの空行がもう入っているので、その分は足さない（同期のたびに空行が増えないように）
        have = len(lines) - len(_rstrip_blank(lines))
        lines += [""] * max(0, int(n.get("tail_blanks", 0)) - have)
        return "\n".join(lines) + "\n"
    # 本文の最後と、その下の節（ChildBranch: など）のあいだの空行は、いつも 1 つだけ。
    # ただし本文がまだ空（見出しの下が空行だけ）の新しいノートは、書き出しの余白（見出しの下に 3 行）を残す。
    # 残さないと、最初の同期で書き込み位置の空行が消え、カーソルが BackLink: の行に来てしまう
    blanks = max(len(lines) - len(_rstrip_blank(lines)), int(n.get("tail_blanks", 0)))
    while lines and lines[-1].strip() == "":
        lines.pop()
    body_text = [ln for ln in (n.get("body") or []) if ln.strip()]
    empty_body = len(body_text) <= 1 and all(ln.startswith("# ") for ln in body_text)
    # 本文の最後がリンク行なら、下の節にくっつける（空行を入れない）。文章なら空行 1 つで区切る。
    # 上の先頭のブロック（Group: など）の一部のリンク・日記の一覧は、今までどおり空行で区切る。
    glue = (not empty_body and not is_timeline and bool(lines) and bool(_SIMPLE_LINK_LINE_RE.match(lines[-1]))
            and not _ends_in_label_block(lines))
    lines += [] if glue else [""] * (3 if blanks >= 3 and empty_body else 1)
    for mark, ls in sections:
        lines.append(mark)
        lines += ls
        while lines and lines[-1].strip() == "":
            lines.pop()
    return "\n".join(lines) + "\n"


def _editor_has_unsaved_changes(path: Path) -> bool:
    """編集中マーカーがあるファイルを background sync は書き換えない。

    Vim が生成したマーカーは Gnosis ホームの state/sync-dirty に置かれ、
    PID のプロセスが生きている間だけ有効。クラッシュ後の古いファイルは除去する。
    CLI 等で Gnosis 以外から呼ばれたときは従来どおり処理する。
    """
    guard_dir = os.environ.get("GNOSIS_SYNC_GUARD_DIR", "")
    if not guard_dir:
        return False
    digest = hashlib.sha256(str(path.resolve()).encode("utf-8")).hexdigest()[:16]
    for marker in Path(guard_dir).glob(f"{digest}.*.dirty"):
        try:
            pid = int(marker.name.split(".")[1])
            if pid <= 0:
                continue
            os.kill(pid, 0)
        except ProcessLookupError:
            try:
                marker.unlink()
            except OSError:
                pass
            continue
        except PermissionError:
            pass  # PID exists but is owned by another user
        except (ValueError, OSError):
            continue
        return True
    return False


# =============================================================================
# 【現役エンジン】 simple_sync 〜
#   CLI の update / update_one / new / retitle_links が呼ぶのはこちら。
#   ノートを実際に書き換えるのはこの経路。
# =============================================================================
def _simple_sync_unlocked(root, old_titles: dict | None = None) -> int:
    """old_titles: {ノートのパス: 変更前のタイトル}。タイトルを変えた瞬間に呼び出し側
    （Vim）が渡す。表示名がこの旧タイトルと同じリンクだけ新タイトルへ追従させる
    （状態ファイルは持たない）。"""
    root = Path(root).resolve()
    # 内容が前回と同じファイルは、読み込んだテキストのハッシュ照合でパースを省く。
    # 読み込み自体は全ファイル分行う（mtime は信用しない。上記コメント参照）。
    cache = _load_parse_cache(root)
    group_state = _load_group_state(root)
    group_state_new: dict[str, list] = dict(group_state)
    fresh_text: dict[Path, str] = {}
    notes: dict[Path, dict] = {}
    keys: dict[Path, str] = {}
    parsed_any = False
    for p in _iter_md(root):
        rp = p.resolve()
        key = _nid(rp, root)
        try:
            text = p.read_text(encoding="utf-8")
        except OSError:
            continue
        h = _content_hash(text)
        ent = cache.get(key) if key is not None else None
        if key is not None and group_state.get(key):
            # Group を記録済みのノートだけ、実ファイルの内容を取っておく（キャッシュの解析結果は
            # sync が自動で足した所属を含まないことがあるので、「今ファイルにある Group」はこちらで見る）。
            fresh_text[rp] = text
        if isinstance(ent, list) and len(ent) == 13 and ent[0] == h:
            notes[rp] = {"fm": ent[1], "title": ent[2], "body": ent[3],
                         "parent": ent[4], "group": ent[5], "related": ent[6],
                         "back": ent[7], "tail_blanks": ent[8],
                         "pbranch": ent[9], "cbranch": ent[10], "ctx": ent[11], "ctx_at": ent[12], "hash": h}
        else:
            notes[rp] = _simple_parse_text(p, text)
            parsed_any = True
        if key is not None:
            keys[rp] = key
    # 削除（ゴミ箱移動を含む）されたフォルゲゼッテル/トピックノートの画像も退避（2026-10-09）
    _trash_zk_note_images(root, cache, set(keys.values()),
                          [(p.parent, n["title"], n["body"]) for p, n in notes.items()])
    # このノートを Context にしているノート（ChildBranch: の並びで上に出す）
    for cp, cn in notes.items():
        for _d, tg in _links_from(cn.get("ctx") or []):
            raw = tg.split("#", 1)[0]
            for cand in (raw, unquote(raw)):
                q = (cp.parent / cand).resolve()
                if q in notes:
                    notes[q].setdefault("_ctx_kids", set()).add(cp)
                    break
        # 子の側の ParentBranch:（親の ChildBranch: に無くても、子として扱う）
        for _d, tg in _links_from(cn.get("pbranch") or []):
            raw = tg.split("#", 1)[0]
            for cand in (raw, unquote(raw)):
                q = (cp.parent / cand).resolve()
                if q in notes:
                    notes[q].setdefault("_pb_kids", set()).add(cp)
                    cn.setdefault("_pb_parents", set()).add(q)
                    break
    # 子の ParentBranch: を手で消したとき、親の ChildBranch: からも外す。前回そろっていた組が片側だけになったら「消した」。
    # （片側だけを手で書いた ChildBranch: は、そろっていた記録が無いので、そのまま残る）
    branch_pairs_prev = _load_branch_pairs(root)
    branch_pairs_now: set[str] = set()
    for pp, pn in notes.items():
        for _d, tg in _links_from(pn.get("cbranch") or []):
            raw = tg.split("#", 1)[0]
            for cand in (raw, unquote(raw)):
                q = (pp.parent / cand).resolve()
                if q in notes:
                    if pp in notes[q].get("_pb_parents", ()):
                        branch_pairs_now.add(_nid(pp, root) + "\t" + _nid(q, root))
                    elif (_nid(pp, root) + "\t" + _nid(q, root)) in branch_pairs_prev:
                        pn.setdefault("_stale_kids", set()).add(q)
                    break
    for cp, cn in notes.items():
        for q in cn.get("_pb_parents", ()):
            branch_pairs_now.add(_nid(q, root) + "\t" + _nid(cp, root))
    # 外すと決めた行は、解析結果（キャッシュに残る）からも取り除く。残すと、次の sync でキャッシュから戻ってしまう
    for pp, pn in notes.items():
        if pn.get("_stale_kids"):
            keep = []
            for ln in pn.get("cbranch") or []:
                tgs = []
                for _d, tg in _links_from([ln]):
                    raw = tg.split("#", 1)[0]
                    tgs.append(next((q for q in ((pp.parent / c).resolve() for c in (raw, unquote(raw))) if q in notes), None))
                if tgs and all(t is not None and t in pn["_stale_kids"] for t in tgs):
                    continue
                keep.append(ln)
            pn["cbranch"] = keep
    # Folgezettel の番号は、子の ParentBranch: を消したときの「親の ChildBranch: から外す」処理のあとで決める
    # （先に決めると、親の ChildBranch: がまだ残っていて、親を外したノートの番号が 1 回の同期で外れない）
    import folgezettel as fz
    for p, ident in fz.allocation(root, notes).items():
        fm = notes[p]["fm"] or ["---", "---"]
        updated = fz.set_value("\n".join(fm), ident) if ident else fz.remove_value("\n".join(fm))
        notes[p]["fm"], _ = _split_front_matter(updated.splitlines())
    # Numbers are recalculated before rendering, so the ChildBranch order
    # always matches the CURRENT Folgezettel order, not the previous sync.
    child_numbers = {p: fz.value("\n".join(n["fm"])) for p, n in notes.items()}
    for n in notes.values():
        n["_child_numbers"] = child_numbers
    titles = {p: n["title"] for p, n in notes.items()}
    # One lookup per target note for zo fragment labels during this sync pass.
    heading_labels = {p: _heading_labels(n["body"]) for p, n in notes.items()}

    # 変更前のタイトル（呼び出し側が渡したものだけ）。本文リンクの表示名を
    # 「追従／手書きを残す」と判定するのに使う（§_update_body_link_names）。
    # 表示名 == 旧タイトルなら自動で付いた名前とみなして新タイトルへ追従し、
    # それ以外の手書き名は残す。
    prev_titles: dict[Path, str] = {}
    for tp, ot in (old_titles or {}).items():
        rp = Path(tp).resolve()
        if rp in notes and ot:
            prev_titles[rp] = ot
    # 明示的な旧タイトルが無い場合も、直前の parse cache に残る題名を使う。
    # キャッシュは同期直前の内容ハッシュで照合されるため、再同期時の誤追従は防げる。
    for p, n in notes.items():
        if p in prev_titles:
            continue
        ent = cache.get(keys.get(p))
        if isinstance(ent, list) and len(ent) >= 3 and isinstance(ent[2], str):
            if ent[2] != n["title"]:
                prev_titles[p] = ent[2]

    # リンク先の解決。Path.resolve() は 1 リンクごとに実パス解決（lstat 連鎖）を
    # して重いので、正規化した文字列で辞書を引く（vault 内は symlink 無しが前提。
    # 見つからないときだけ従来の resolve にフォールバックする）。
    notes_by_norm = {os.path.normpath(str(k)): k for k in notes}
    dirs: dict[Path, str] = {p: str(p.parent) for p in notes}

    def res(tg: str, base) -> Path | None:
        base_s = base if isinstance(base, str) else str(base)
        if tg.startswith("/"):
            cand = os.path.normpath(tg)
        else:
            cand = os.path.normpath(os.path.join(base_s, tg))
        rp = notes_by_norm.get(cand)
        if rp is not None:
            return rp
        base_p = Path(base_s)
        try:
            tp = Path(tg).resolve() if tg.startswith("/") else (base_p / tg).resolve()
        except OSError:
            return None
        return tp if tp in notes else None

    member_names: dict[Path, dict[Path, list[str]]] = {}
    body_t: dict[Path, list[Path]] = {}
    for p, n in notes.items():
        ts: list[Path] = []
        n["body"] = _update_body_link_names(n["body"], p, res, titles, prev_titles)
        names: dict[Path, list[str]] = {}
        for display, tg in _links_from(n["body"]):
            rp = res(tg, dirs[p])
            if rp is not None and rp != p:
                ts.append(rp)
                labels = names.setdefault(rp, [])
                if display not in labels:
                    labels.append(display)
        member_names[p] = names
        body_t[p] = ts

    incoming: dict[Path, list[Path]] = {p: [] for p in notes}
    for src, ts in body_t.items():
        for t in dict.fromkeys(ts):
            incoming[t].append(src)

    # index.md は見張り（### Parent / ### BackLink）を持たない。Index 本文の
    # リンクは「そのノートの親に Index が載る」構造を意味するので、
    # リンク先の Parent 先頭に `[Index](index.md)` を入れ、BackLink には
    # 出さない。§index.md（03-同期の規則）。
    index_of: dict[Path, Path] = {}
    for p, n in notes.items():
        if p.name != "index.md":
            continue
        for t in body_t.get(p, []):
            if t != p:
                index_of[t] = p

    # 使われていない表示名の yomi を掃除する（\zy で登録した表示名が Index から
    # 消えたら、同期時に一緒に消える）。ノート自身の title は incoming があるときだけ残す。
    _yomi_to_store(root, notes)
    _used = _used_display_names(notes, incoming)
    _prune_yomi_maps(notes, _used)
    _prune_yomi_store(root, notes, _used)

    # `### Related` は対称。両側に同じ相手があるペアだけ成立する（zr は両側に
    # 書くので通常はそのまま）。片側で消されたら次回 sync で反対側からも消える。
    # 表示名はタイトルに追従し、消えたファイルへのリンクは掃除する。
    for p, n in notes.items():
        n["related"] = _preserve_parent(n["related"], p, res, titles, heading_labels)
        n["related"] = _prune_dangling(n["related"], p, res)
        # ParentBranch / ChildBranch もユーザーが `b` で明示した関係。同期は追加も削除もしない
        # （表示名の追従と、消えたファイルへのリンクの掃除だけ）。Context へ変換もしない。
        for key in ("pbranch", "cbranch"):
            n[key] = _preserve_parent(n[key], p, res, titles, heading_labels)
            n[key] = _prune_dangling(n[key], p, res)
    related_t: dict[Path, set[Path]] = {}
    for p, n in notes.items():
        ts: set[Path] = set()
        for _d, tg in _links_from(n["related"]):
            rp = res(tg, dirs[p])
            if rp is not None and rp != p:
                ts.add(rp)
        related_t[p] = ts
    for p, n in notes.items():
        n["related"] = _prune_one_sided_related(n["related"], p, res, related_t)

    # グループ（attribute: group / index.md）の集合。ノートごとに全ノート分を
    # 再計算していたため O(N²) になっていた（1,000 ノートで re.search 100 万回）。
    # 1 回だけ作って使い回す。
    group_set = {q for q, nn in notes.items()
                 if q.name == "index.md"
                 or (nn["fm"] and _GROUP_ATTR_RE.search("\n".join(nn["fm"])))}

    # 親の本文から消えた子リンクを見つける（前回 sync 時点の本文と比べる）。
    # 消えた子の Parent からは、その親（＝本文から消した側）を外す。手で足した Parent も、
    # 「本文のリンクを消した」ときだけ対象になる（本文に無い Parent は触らない）。
    removed_parent_of: dict[Path, set[Path]] = {}
    for p, n in notes.items():
        key = keys.get(p)
        ent = cache.get(key) if key is not None else None
        if not (isinstance(ent, list) and len(ent) in (9, 11, 13)):  # 9 / 11 = 旧キャッシュ
            continue
        old_targets = {rp for _d, tg in _links_from(ent[3])
                       for rp in [res(tg, dirs[p])] if rp is not None and rp != p}
        new_targets = {rp for _d, tg in _links_from(n["body"])
                       for rp in [res(tg, dirs[p])] if rp is not None and rp != p}
        for child in old_targets - new_targets:
            if child in notes:
                removed_parent_of.setdefault(child, set()).add(p)

    # 子の Group: からグループへのリンクを消した → そのグループの本文からも、この子へのリンクを外す
    # （消さないと、次の sync が Group: へ自動で戻してしまう）。前回 sync 時点の Group と比べる。
    # Context / ParentBranch など別の関係として残っているリンクは「消した」とみなさない。
    removed_group_of: dict[Path, set[Path]] = {}
    for p, n in notes.items():
        key = keys.get(p)
        recorded = group_state.get(key) if key is not None else None
        if not isinstance(recorded, list):
            continue
        old_groups = {rp for _d, tg in _links_from(recorded)
                      for rp in [res(tg, dirs[p])] if rp is not None and rp != p}
        cur = _simple_parse_text(p, fresh_text[p]) if p in fresh_text else n
        still = {rp for _d, tg in _links_from(cur["group"] + cur["ctx"] + cur["parent"] + cur["pbranch"] + cur["cbranch"])
                 for rp in [res(tg, dirs[p])] if rp is not None}
        for g in old_groups - still:
            if g in notes and g in group_set:
                removed_group_of.setdefault(p, set()).add(g)
    for p, gs in removed_group_of.items():
        for g in gs:
            kept: list[str] = []
            for ln in notes[g]["body"]:
                tgt = _link_target(ln) if _SIMPLE_LINK_LINE_RE.match(ln) else None
                if tgt and res(tgt, dirs[g]) == p:
                    continue
                kept.append(ln)
            notes[g]["body"] = kept

    changed = 0
    for p, n in notes.items():
        # 本文リンクの表示名をリンク先タイトルに追従させ、消えたファイルへの
        # リンクは掃除する（文章中に埋もれたリンクは表示名の文字だけ残す）。
        n["body"] = _update_body_link_names(n["body"], p, res, titles, prev_titles)
        n["body"] = _prune_dangling(n["body"], p, res)
        # Context（旧 Parent）と Group はユーザー管理（追加・削除はしない）。ただし消えた
        # ファイルへのリンクは残骸なので掃除する（行全体がリンクの行のみ）。表示名は追従。
        # 新形式（本文冒頭の `Context:` ブロック）があれば、旧形式の節のリンクも合わせて 1 つのブロックにする
        # （リンクは 1 本も失わない）。旧形式だけのノートは旧形式のまま（sync は勝手に移行しない）。
        if n["ctx_at"] >= 0:
            legacy_links = [ln for ln in n["parent"] if _SIMPLE_LINK_LINE_RE.match(ln)]
            n["_leftover"] = [ln for ln in n["parent"] if ln.strip() and not _SIMPLE_LINK_LINE_RE.match(ln)]
            seen_ctx: set[str] = set()
            parent_src: list[str] = []
            for ln in n["ctx"] + legacy_links:
                if ln.strip() not in seen_ctx:
                    seen_ctx.add(ln.strip())
                    parent_src.append(ln)
        else:
            parent_src = list(n["parent"])
            n["_leftover"] = []
        parent_lines = _preserve_parent(parent_src, p, res, titles, heading_labels)
        parent_lines = _prune_dangling(parent_lines, p, res)
        branch_links, _, _ = _take_branch_group_block(n["body"])
        branch_targets = {rp for _display, tg in _links_from(branch_links)
                          for rp in [res(tg, dirs[p])] if rp is not None}
        group_lines = _preserve_parent(n["group"], p, res, titles, heading_labels)
        group_lines = _prune_dangling(group_lines, p, res)
        parent_set: set[Path] = set()
        for _d, tg in _links_from(parent_src + n["group"]):
            rp = res(tg, dirs[p])
            if rp is not None:
                parent_set.add(rp)
        # 親の本文からリンクを消した → この子の Context / Group からその親を外す
        gone = removed_parent_of.get(p, set())
        if gone:
            def _drop_gone(lines, gone=gone, p=p):
                keep_l: list[str] = []
                for ln in lines:
                    tgt = _link_target(ln)
                    rp = res(tgt, dirs[p]) if tgt else None
                    if rp is not None and rp in gone:
                        continue
                    keep_l.append(ln)
                return keep_l
            parent_lines = _drop_gone(parent_lines)
            group_lines = _drop_gone(group_lines)
            parent_set -= gone
        # index.md 側のリンク = 親（グループ）。
        #   - Index の本文にこのノートがある  → Group 先頭に [Index] を置く
        #   - 無いのに [Index] が残っている → 外す（放置させない）
        # Index との対応は sync が管理する（残骸を掃除する）。
        gone_groups = removed_group_of.get(p, set())
        idx = index_of.get(p)
        if idx is not None and idx not in parent_set and idx not in gone_groups:
            parent_set.add(idx)
            rel = _rel(p.parent, idx)
            group_lines.insert(0, f"[{titles[idx]}]({rel})")
        elif idx is None:
            drop: set[Path] = set()

            def _drop_index(lines, p=p):
                keep_l: list[str] = []
                for ln in lines:
                    tgt = _link_target(ln)
                    rp = res(tgt, dirs[p]) if tgt else None
                    if rp is not None and rp.name == "index.md":
                        drop.add(rp)
                    else:
                        keep_l.append(ln)
                return keep_l
            parent_lines = _drop_index(parent_lines)
            group_lines = _drop_index(group_lines)
            parent_set -= drop
        # グループ → 子供 の判定:
        #   - 本文でリンクしている相手がグループ（index.md を含む）なら、そのリンクは
        #     「グループ → 子供」という containership なので、子の Group に入る。
        #     （グループの本文に自分へのリンクがあれば、自動で Group にそのグループが入る）
        #   - それ以外は BackLink（incoming − Context − Group − 自分）。
        # 既存の並びを保ち、新しく増えた分は末尾に追加する。
        auto_group: list[Path] = []
        desired: list[Path] = []
        dseen: set[Path] = set()
        # 自分の本文（outgoing）または Related にもリンクがある相手は BackLink に
        # 出さない（同じリンクの繰り返しになる）。Related は相互に書くので、
        # 両側に Related があるペアは BackLink には現れない。
        out_set = set(body_t.get(p, []))
        for _d, tg in _links_from(n["related"] + n["cbranch"]):
            rp = res(tg, dirs[p])
            if rp is not None and rp != p:
                out_set.add(rp)
        # 自分の ParentBranch にいる相手（親）は BackLink に出さない（関係として別に載っている）。
        # Context / Group の判定（parent_set）には混ぜない（グループの自動所属を止めないため）。
        pb_set: set[Path] = set()
        for _d, tg in _links_from(n["pbranch"]):
            rp = res(tg, dirs[p])
            if rp is not None and rp != p:
                pb_set.add(rp)
        for s in incoming.get(p, []):
            if s == p or s in dseen or s in out_set:
                continue
            dseen.add(s)
            if s in group_set:
                if s not in gone_groups:
                    auto_group.append(s)
                continue
            if s in parent_set or s in pb_set:
                continue
            desired.append(s)
        for s in auto_group:
            if s in parent_set or s in branch_targets:
                continue
            parent_set.add(s)
            group_lines.append(f"[{titles[s]}]({_rel(p.parent, s)})")

        # Context と Group の仕分け: グループへのリンクは Group、普通のノートへのリンクは
        # Context。文字・空行・ノート以外へのリンクは動かさない。
        def _link_kind(ln: str, p=p):
            if not _SIMPLE_LINK_LINE_RE.match(ln):
                return None
            tg = _link_target(ln)
            rp = res(tg, dirs[p]) if tg else None
            return None if rp is None else rp in group_set

        moved = False
        new_ctx: list[str] = []
        for ln in parent_lines:
            if _link_kind(ln) is True:
                group_lines.append(ln)
                moved = True
            else:
                new_ctx.append(ln)
        new_grp: list[str] = []
        for ln in group_lines:
            if _link_kind(ln) is False:
                new_ctx.append(ln)
                moved = True
            else:
                new_grp.append(ln)
        parent_lines, group_lines = new_ctx, new_grp
        # ParentBranch is stronger than Context: do not repeat the same target
        # under Context, including duplicates in previously synced vaults.
        # Keep all unrelated Context links and non-link notes intact.
        pb_targets = {res(tg.split("#", 1)[0], dirs[p])
                      for _d, tg in _links_from(n.get("pbranch") or [])}
        pb_targets.discard(None)
        if pb_targets:
            parent_lines = [
                ln for ln in parent_lines
                if not (_SIMPLE_LINK_LINE_RE.match(ln)
                        and res((_link_target(ln) or "").split("#", 1)[0], dirs[p]) in pb_targets)
            ]
            parent_lines = _tidy_blanks(parent_lines)
        # 同じ相手のリンクが Group に重なったら 1 本にする
        seen_g: set[Path] = set()
        dedup: list[str] = []
        for ln in group_lines:
            if _link_kind(ln) is True:
                rp = res(_link_target(ln), dirs[p])
                # BranchGroup にあるグループを通常 Group に重複表示しない。
                if rp in branch_targets or rp in seen_g:
                    continue
                seen_g.add(rp)
                labels = member_names.get(rp, {}).get(p, [])
                if labels:
                    target = _SIMPLE_INLINE_LINK.search(ln).group(2)
                    ln = f"[{titles[rp]}:{','.join(labels)}]({target})"
            dedup.append(ln)
        group_lines = dedup
        if moved:
            parent_lines = _tidy_blanks(parent_lines)
            group_lines = _tidy_blanks(group_lines)
        existing_back: list[Path] = []
        for _d, tg in _links_from(n["back"]):
            rp = res(tg, dirs[p])
            if rp is not None and rp not in existing_back:
                existing_back.append(rp)
        dset = set(desired)
        back = [t for t in existing_back if t in dset]
        back += [t for t in desired if t not in set(back)]
        new_text = _simple_render(p.name, n, p, parent_lines, back, titles, group_lines)
        new_hash = _content_hash(new_text)
        gkey = keys.get(p)
        if new_hash == n["hash"] and gkey is not None:
            group_state_new[gkey] = [ln for ln in group_lines if ln.strip()]
        if new_hash != n["hash"]:
            # 保存済みの入力を同期のスナップショットで上書きしない。
            # 1. Vim の未保存編集（InsertEnter/TextChanged）中は書かない
            # 2. 同期開始時に読んだファイルが途中で変わっていたら書かない
            #    （別の自動保存 / 並行同期が先に保存した場合）
            if _editor_has_unsaved_changes(p):
                continue
            try:
                if _content_hash(p.read_text(encoding="utf-8")) != n["hash"]:
                    continue
            except OSError:
                continue
            p.write_text(new_text, encoding="utf-8")
            changed += 1
            n["hash"] = new_hash
            if gkey is not None:
                group_state_new[gkey] = [ln for ln in group_lines if ln.strip()]
    # 次回の判定のため、今回のパース結果と最終ハッシュを保存する。全件が
    # キャッシュヒットで何も書き換えていないなら、内容は前回と同一なので
    # 数 MB の JSON を書き直さない（保存のたびに走るため無駄が大きい）。
    if group_state_new != group_state:
        _save_group_state(root, group_state_new)
    if branch_pairs_now != branch_pairs_prev:
        _save_branch_pairs(root, branch_pairs_now)
    if parsed_any or changed:
        out_cache: dict[str, list] = {}
        for p, n in notes.items():
            key = keys.get(p)
            if key is None:
                continue
            out_cache[key] = [n["hash"], n["fm"], n["title"], n["body"],
                              n["parent"], n["group"], n["related"], n["back"],
                              n.get("tail_blanks", 0), n["pbranch"], n["cbranch"], n["ctx"], n["ctx_at"]]
        _save_parse_cache(root, out_cache)
    return changed


def _sync_lock_path(root: Path) -> Path | None:
    """同じ vault の同期どうしを順番にするロックファイル。Gnosis ホームの state/sync-locks に vault ごとに置く
    （vault の中には作らない。別の vault とは何も共有しない）。Gnosis の外から呼ばれたとき（環境変数なし）は None。"""
    guard = os.environ.get("GNOSIS_SYNC_GUARD_DIR", "")
    if not guard:
        return None
    digest = hashlib.sha256(str(Path(root).resolve()).encode("utf-8")).hexdigest()[:16]
    return Path(guard).parent / "sync-locks" / f"{digest}.lock"


@contextlib.contextmanager
def vault_lock(root, timeout: float = 30.0):
    """同じ vault の同期・Branch 追加どうしを順番にする排他（flock。ロックが取れたら True、待ちきれなければ False を渡す）。
    持ち主のプロセスが終われば（異常終了でも）OS が外す。Gnosis の外から呼ばれたとき・Windows では排他なしで True。"""
    lock_path = _sync_lock_path(Path(root))
    if lock_path is None:
        yield True
        return
    try:
        import fcntl
    except ImportError:
        yield True
        return
    try:
        lock_path.parent.mkdir(parents=True, exist_ok=True)
        fh = open(lock_path, "a+")
    except OSError:
        yield True
        return
    got = False
    try:
        import time
        deadline = time.monotonic() + timeout
        while True:
            try:
                fcntl.flock(fh, fcntl.LOCK_EX | fcntl.LOCK_NB)
                got = True
                break
            except OSError:
                if time.monotonic() > deadline:
                    break
                time.sleep(0.05)
        yield got
    finally:
        if got:
            try:
                fcntl.flock(fh, fcntl.LOCK_UN)
            except OSError:
                pass
        fh.close()


def simple_sync(root, old_titles: dict | None = None, lock_timeout: float = 30.0) -> int:
    """同期の本体（_simple_sync_unlocked）を、同じ vault を別のウィンドウ・プロセスが同期している間は待ってから行う。
    待ちきれなければこの回は何もしない（相手の同期が同じ内容を処理している）。"""
    with vault_lock(root, lock_timeout) as got:
        if not got:
            return 0
        return _simple_sync_unlocked(root, old_titles)


def update_one(file_path, root, old_title: str = "") -> str:
    changed = simple_sync(root, {file_path: old_title} if old_title else None)
    return f"Gnosis: synced {changed} file(s)" if changed else "Gnosis: no changes"


# ---------------------------------------------------------------------------
# new note
# ---------------------------------------------------------------------------

def make_new(path, title: str = "") -> Path:
    p = Path(path)
    ts = _dt.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    t = title.strip() or p.stem
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(
        f"---\ntime: {ts}\n---\n\n# {t}\n\n\n",
        encoding="utf-8",
    )
    return p


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main(argv: list[str]) -> int:
    if len(argv) < 3:
        print(__doc__, file=sys.stderr)
        return 2
    mode = argv[1]
    if mode == "update":
        changed = simple_sync(argv[2])
        print(f"Gnosis: updated {changed} file(s) under {argv[2]}")
        return 0
    if mode == "update_one":
        if len(argv) < 4:
            print("usage: note_format_v2.py update_one FILE ROOT", file=sys.stderr)
            return 2
        print(update_one(argv[2], argv[3], argv[4] if len(argv) > 4 else ""))
        return 0
    if mode == "new":
        if len(argv) < 4:
            print("usage: note_format_v2.py new FILE ROOT [TITLE]", file=sys.stderr)
            return 2
        title = argv[4] if len(argv) > 4 else ""
        p = make_new(argv[2], title)
        simple_sync(argv[3])
        print(str(p))
        return 0
    if mode == "retitle_links":
        # retitle_links TARGET ROOT [OLD_TITLE [NEW_TITLE]]
        if len(argv) >= 4:
            old = argv[4] if len(argv) > 4 else ""
            simple_sync(argv[3], {argv[2]: old} if old else None)
        print("Gnosis: retitle via sync")
        return 0
    if mode == "migrate":
        # 明示的な変換。sync は旧形式を触らないので、これを 1 回走らせて v2 化する。
        if len(argv) < 3:
            print("usage: note_format_v2.py migrate ROOT [FILE]", file=sys.stderr)
            return 2
        root = Path(argv[2]).resolve()
        targets = [Path(argv[3])] if len(argv) > 3 else list(_iter_md(root))
        done = 0
        for tp in targets:
            try:
                cur = tp.read_text(encoding="utf-8")
            except OSError:
                continue
            new = migrate_note(cur, str(tp))
            if new and new != cur:
                tp.write_text(new, encoding="utf-8")
                done += 1
        if done:
            sync_vault(root)
        print(f"Gnosis: v2 migrated {done} file(s)")
        return 0
    if mode == "dupcheck":
        # 2 つの vault を merge する前に、同名 .md（＝タイムスタンプ衝突）を洗い出す。
        if len(argv) < 4:
            print("usage: note_format_v2.py dupcheck DIR_A DIR_B", file=sys.stderr)
            return 2
        a = {p.name for p in Path(argv[2]).rglob("*.md")} - {"index.md"}
        b = {p.name for p in Path(argv[3]).rglob("*.md")} - {"index.md"}
        dup = sorted(a & b)
        if dup:
            print("衝突するファイル名（merge 前にどちらかを改名）:")
            for name in dup:
                print(f"  {name}")
            return 1
        print("衝突なし（index.md を除く）")
        return 0
    if mode in {"update_titles", "rename_prefix", "reparent_down_children", "nf"}:
        print(f"Gnosis: v2 ignores mode '{mode}'", file=sys.stderr)
        return 0
    print(f"unsupported mode: {mode}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
