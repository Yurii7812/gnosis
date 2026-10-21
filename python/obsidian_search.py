#!/usr/bin/env python3
"""Obsidian と同じ書き方の全文検索（`\\A` の左のバーの「検索」）。読み取り専用。

書き方（Obsidian の検索と同じ）:
  りんご みかん        両方を含むノート（AND。語はノートのどこにあってもよい）
  "りんご ジャム"      その並びのまま
  りんご OR みかん     どちらか（OR は大文字）
  -みかん              含まないノート
  (a OR b) c           かっこでまとめる
  /\\d{4}-\\d\\d/       正規表現（JavaScript と同じく / で囲む）
  file:旅行            ファイル名（Gnosis ではノートの題も）に含む
  path:日記/           パス（vault からの相対）に含む
  content:旅行         本文だけで探す（ファイル名は見ない）
  line:(小麦粉 砂糖)   同じ行に両方
  block:(a b)          同じ段落（空行で区切られたまとまり）に両方
  section:(a b)        同じ節（見出しから次の見出しまで）に両方
  tag:#料理            タグ（本文の #料理・front matter の tags）
  task:買う            チェックボックスの行（task-todo: は未完了・task-done: は完了だけ）
  match-case:Gnosis    大文字・小文字を区別（ignore-case: は区別しない）
  [title]              front matter にその項目があるノート
  [status:進行中]      front matter の項目の値に含む
  演算子の後ろには語・"…"・( … )・/…/ が書ける（例: file:("旅行 計画")、line:(/^- /)）。

大文字と小文字は既定では区別しない（match_case=True で区別。Obsidian の「大文字と小文字を区別」と同じ）。
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field

SCOPES = {"file", "path", "content", "line", "block", "section", "tag", "task", "task-todo", "task-done", "match-case", "ignore-case"}


# ---------------------------------------------------------------- 構文木
@dataclass
class Term:
    kind: str            # text | phrase | regex
    value: str
    case: bool | None = None   # None: 全体の設定に従う

@dataclass
class And:
    items: list

@dataclass
class Or:
    items: list

@dataclass
class Not:
    item: object

@dataclass
class Scope:
    op: str
    item: object

@dataclass
class Prop:
    name: str
    value: object | None = None


class QueryError(ValueError):
    pass


# ---------------------------------------------------------------- 字句と構文
def _tokens(q: str) -> list[tuple[str, str]]:
    """("(" | ")" | "-" | "OR" | "op" | "quote" | "regex" | "word" | "prop", 文字)"""
    out, i, n = [], 0, len(q)
    while i < n:
        ch = q[i]
        if ch.isspace():
            i += 1
            continue
        if ch in "()":
            out.append((ch, ch)); i += 1; continue
        if ch == "-" and i + 1 < n and not q[i + 1].isspace() and (not out or out[-1][0] in ("(", "-", "OR", "op") or i == 0 or q[i - 1].isspace() or q[i - 1] == "("):
            out.append(("-", "-")); i += 1; continue
        if ch == '"':
            j = i + 1
            buf = []
            while j < n and q[j] != '"':
                if q[j] == "\\" and j + 1 < n:
                    buf.append(q[j + 1]); j += 2; continue
                buf.append(q[j]); j += 1
            out.append(("quote", "".join(buf))); i = j + 1; continue
        if ch == "/":
            j = i + 1
            while j < n and q[j] != "/":
                j += 2 if q[j] == "\\" else 1
            if j < n:
                out.append(("regex", q[i + 1:j])); i = j + 1; continue
        if ch == "[":
            j = q.find("]", i + 1)
            if j > 0:
                out.append(("prop", q[i + 1:j])); i = j + 1; continue
        # 語（空白・かっこ・引用符まで）。「op:」なら演算子
        j = i
        while j < n and not q[j].isspace() and q[j] not in '()"':
            j += 1
        word = q[i:j]
        m = re.match(r"^([a-z-]+):(.*)$", word)
        if m and m.group(1) in SCOPES:
            out.append(("op", m.group(1)))
            rest = m.group(2)
            if rest:
                out.append(("regex", rest[1:-1]) if len(rest) > 1 and rest.startswith("/") and rest.endswith("/") else ("word", rest))
            i = j
            continue
        out.append(("OR", word) if word == "OR" else ("word", word))
        i = j
    return out


def parse(q: str):
    toks = _tokens(q)
    pos = 0

    def peek():
        return toks[pos] if pos < len(toks) else (None, None)

    def take():
        nonlocal pos
        t = toks[pos]; pos += 1
        return t

    def p_or():
        items = [p_and()]
        while peek()[0] == "OR":
            take()
            items.append(p_and())
        items = [x for x in items if x is not None]
        return items[0] if len(items) == 1 else (Or(items) if items else None)

    def p_and():
        items = []
        while peek()[0] not in (None, ")", "OR"):
            x = p_unary()
            if x is not None:
                items.append(x)
        return items[0] if len(items) == 1 else (And(items) if items else None)

    def p_unary():
        k, v = peek()
        if k == "-":
            take()
            x = p_unary()
            return Not(x) if x is not None else None
        if k == "op":
            take()
            if peek()[0] in (None, ")", "OR"):
                return None          # 「file:」だけ（打っている途中）
            x = p_unary()
            return Scope(v, x) if x is not None else None
        return p_atom()

    def p_atom():
        k, v = take()
        if k == "(":
            x = p_or()
            if peek()[0] == ")":
                take()
            return x
        if k == ")":
            return None
        if k == "quote":
            return Term("phrase", v) if v else None
        if k == "regex":
            try:
                re.compile(_js_regex(v))
            except re.error as e:
                raise QueryError(f"正規表現が読めません: /{v}/（{e}）")
            return Term("regex", v)
        if k == "prop":
            name, _, val = v.partition(":")
            return Prop(name.strip(), (parse(val) if val.strip() else None))
        return Term("text", v)

    node = p_or()
    while pos < len(toks):     # 余った「)」は読み飛ばす
        take()
        rest = p_or()
        if rest is not None:
            node = And([node, rest]) if node is not None else rest
    return node


def _js_regex(v: str) -> str:
    # JavaScript の書き方のうち Python と違うものだけ直す（名前付きグループ）
    return v.replace("(?<", "(?P<").replace("(?P<=", "(?<=").replace("(?P<!", "(?<!")


# ---------------------------------------------------------------- 説明（Obsidian の「検索語の説明」）
def explain(node, depth: int = 0) -> str:
    if node is None:
        return ""
    pad = "  " * depth
    if isinstance(node, Term):
        what = {"text": f"「{node.value}」", "phrase": f"「{node.value}」（この並びのまま）", "regex": f"正規表現 /{node.value}/"}[node.kind]
        return pad + f"{what}を含む" + ("（大文字と小文字を区別）" if node.case else "")
    if isinstance(node, Not):
        return pad + "次を含まない:\n" + explain(node.item, depth + 1)
    if isinstance(node, And):
        return pad + "次をすべて満たす:\n" + "\n".join(explain(x, depth + 1) for x in node.items)
    if isinstance(node, Or):
        return pad + "次のどれかを満たす:\n" + "\n".join(explain(x, depth + 1) for x in node.items)
    if isinstance(node, Scope):
        label = {"file": "ファイル名・題", "path": "パス", "content": "本文", "line": "同じ行", "block": "同じ段落", "section": "同じ節", "tag": "タグ",
                 "task": "チェックボックスの行", "task-todo": "未完了のチェックボックスの行", "task-done": "完了したチェックボックスの行",
                 "match-case": "大文字と小文字を区別して", "ignore-case": "大文字と小文字を区別せず"}[node.op]
        return pad + f"{label}で:\n" + explain(node.item, depth + 1)
    if isinstance(node, Prop):
        return pad + (f"項目 {node.name} があり、その値が:\n" + explain(node.value, depth + 1) if node.value is not None else f"項目 {node.name} がある")
    return ""


# ---------------------------------------------------------------- ノートの形
@dataclass
class Doc:
    rel: str
    title: str
    text: str
    lines: list = field(default_factory=list)
    fm: dict = field(default_factory=dict)
    tags: list = field(default_factory=list)
    _units: dict = field(default_factory=dict)

    @staticmethod
    def make(rel: str, title: str, text: str) -> "Doc":
        d = Doc(rel, title, text, text.split("\n"))
        d.fm = _front_matter(d.lines)
        tags = set()
        fmt = d.fm.get("tags") or d.fm.get("tag")
        for t in (fmt if isinstance(fmt, list) else [fmt] if fmt else []):
            tags.add("#" + str(t).lstrip("#"))
        for m in re.finditer(r"(?:^|\s)(#[^\s#.,:;!?()\[\]{}\"'、。]+)", text):
            if not re.match(r"^#+$", m.group(1)):
                tags.add(m.group(1))
        d.tags = sorted(tags)
        return d

    def units(self, kind: str) -> list[tuple[int, int]]:
        """行のまとまり [始まり, 終わり)（0 から）。line=1 行ずつ・block=空行で区切る・section=見出しで区切る・task=チェックボックスの行。"""
        if kind in self._units:
            return self._units[kind]
        L = self.lines
        out: list[tuple[int, int]] = []
        if kind == "line":
            out = [(i, i + 1) for i in range(len(L))]
        elif kind.startswith("task"):
            want = {"task": "[ xX/-]", "task-todo": "[ ]", "task-done": "[xX]"}[kind]
            rx = re.compile(r"^\s*(?:[-*+]|\d+[.)])\s+\[" + want + r"\]\s")
            out = [(i, i + 1) for i, ln in enumerate(L) if rx.match(ln)]
        elif kind == "block":
            s = None
            for i, ln in enumerate(L + [""]):
                if ln.strip():
                    s = i if s is None else s
                elif s is not None:
                    out.append((s, i)); s = None
        elif kind == "section":
            starts = [0] + [i for i, ln in enumerate(L) if re.match(r"^#{1,6}\s", ln)]
            starts = sorted(set(starts))
            out = [(a, b) for a, b in zip(starts, starts[1:] + [len(L)]) if b > a]
        self._units[kind] = out
        return out


def _front_matter(lines: list[str]) -> dict:
    if not lines or lines[0].strip() != "---":
        return {}
    out: dict = {}
    key = None
    for ln in lines[1:]:
        if ln.strip() == "---":
            break
        m = re.match(r"^([A-Za-z0-9_\-ぁ-んァ-ヶ一-龠]+):\s*(.*)$", ln)
        if m:
            key = m.group(1)
            v = m.group(2).strip()
            if v.startswith("[") and v.endswith("]"):
                out[key] = [x.strip().strip("\"'") for x in v[1:-1].split(",") if x.strip()]
            else:
                out[key] = v.strip("\"'")
        elif key and re.match(r"^\s+-\s+", ln):
            cur = out.get(key)
            out[key] = (cur if isinstance(cur, list) else ([cur] if cur else [])) + [re.sub(r"^\s+-\s+", "", ln).strip().strip("\"'")]
    return out


# ---------------------------------------------------------------- 照合
def _finder(t: Term, case: bool):
    """文字列 → 当たった範囲 [(始まり, 終わり)]"""
    cs = t.case if t.case is not None else case
    if t.kind == "regex":
        rx = re.compile(_js_regex(t.value), 0 if cs else re.IGNORECASE)
        return lambda s: [(m.start(), m.end()) for m in rx.finditer(s) if m.end() > m.start()]
    needle = t.value if cs else t.value.casefold()

    def f(s: str):
        hay = s if cs else s.casefold()
        if len(hay) != len(s):        # casefold で長さが変わる文字（ß など）は lower で
            hay, nd = (s, t.value) if cs else (s.lower(), t.value.lower())
        else:
            nd = needle
        out, i = [], hay.find(nd)
        while i >= 0 and nd:
            out.append((i, i + len(nd)))
            i = hay.find(nd, i + len(nd))
        return out
    return f


def _match(node, doc: Doc, case: bool, region: tuple[int, int] | None, where: str) -> tuple[bool, set]:
    """region（行の範囲）か、ノート全体（None）で node が成り立つか。成り立つなら、当たった行の集合も返す。
    where: "all"（本文とファイル名）| "content" | "file" | "path" | "tag" """
    if node is None:
        return True, set()
    if isinstance(node, And):
        hits: set = set()
        for x in node.items:
            ok, h = _match(x, doc, case, region, where)
            if not ok:
                return False, set()
            hits |= h
        return True, hits
    if isinstance(node, Or):
        any_ok, hits = False, set()
        for x in node.items:
            ok, h = _match(x, doc, case, region, where)
            if ok:
                any_ok = True
                hits |= h
        return any_ok, hits
    if isinstance(node, Not):
        ok, _ = _match(node.item, doc, case, region, where)
        return (not ok), set()
    if isinstance(node, Prop):
        keys = {k.casefold(): k for k in doc.fm}
        k = keys.get(node.name.casefold())
        if k is None:
            return False, set()
        if node.value is None:
            return True, set()
        vals = doc.fm[k] if isinstance(doc.fm[k], list) else [doc.fm[k]]
        pseudo = Doc.make(doc.rel, doc.title, "\n".join(str(v) for v in vals))
        ok, _ = _match(node.value, pseudo, case, None, "content")
        return ok, set()
    if isinstance(node, Scope):
        op = node.op
        if op == "match-case":
            return _match(node.item, doc, True, region, where)
        if op == "ignore-case":
            return _match(node.item, doc, False, region, where)
        if op in ("file", "path", "content", "tag"):
            return _match(node.item, doc, case, region, op)
        # line / block / section / task*: どれか 1 つのまとまりの中で全部
        hits: set = set()
        found = False
        for (a, b) in doc.units(op):
            if region and (b <= region[0] or a >= region[1]):
                continue
            ok, h = _match(node.item, doc, case, (a, b), "content")
            if ok:
                found = True
                hits |= (h or set(range(a, b)))
        return found, hits
    # Term
    f = _finder(node, case)
    if where == "file":
        name = doc.rel.rsplit("/", 1)[-1]
        return bool(f(name) or f(name[:-3] if name.endswith(".md") else name) or f(doc.title)), set()
    if where == "path":
        return bool(f(doc.rel)), set()
    if where == "tag":
        want = node.value if node.kind != "regex" else None
        if want is not None:
            w = want if want.startswith("#") else "#" + want
            w = w if (node.case if node.case is not None else case) else w.casefold()
            for t in doc.tags:
                tt = t if (node.case if node.case is not None else case) else t.casefold()
                if tt == w or tt.startswith(w + "/"):
                    return True, {i for i, ln in enumerate(doc.lines) if t in ln}
            return False, set()
        return any(f(t) for t in doc.tags), set()
    a, b = region if region else (0, len(doc.lines))
    hits = {i for i in range(a, b) if f(doc.lines[i])}
    if hits:
        return True, hits
    if region is None and where == "all":
        # Obsidian と同じく、語はファイル名に当たってもよい（Gnosis では題も）
        name = doc.rel.rsplit("/", 1)[-1]
        if f(name) or f(doc.title):
            return True, set()
    return False, set()


def positive_terms(node, under_not: bool = False, scope: str = "") -> list:
    """当たった所に色を付ける語（「含まない」の中・ファイル名やパスだけの語は除く）"""
    if node is None:
        return []
    if isinstance(node, Term):
        return [] if under_not or scope in ("file", "path", "tag") else [node]
    if isinstance(node, Not):
        return positive_terms(node.item, True, scope)
    if isinstance(node, (And, Or)):
        return [t for x in node.items for t in positive_terms(x, under_not, scope)]
    if isinstance(node, Scope):
        if node.op in ("match-case", "ignore-case"):
            inner = positive_terms(node.item, under_not, scope)
            for t in inner:
                if t.case is None:
                    t.case = node.op == "match-case"
            return inner
        return positive_terms(node.item, under_not, node.op)
    return []


def search(docs: list[Doc], query: str, match_case: bool = False, limit_lines: int = 12) -> dict:
    """{results: [{rel, title, count, lines: [{line, text, ranges}]}], total, explain} 。順番は呼ぶ側が決める。"""
    node = parse(query)
    if node is None:
        return {"results": [], "total": 0, "explain": ""}
    terms = positive_terms(node)
    finders = [_finder(t, match_case) for t in terms]
    results = []
    for d in docs:
        ok, hits = _match(node, d, match_case, None, "all")
        if not ok:
            continue
        lines = []
        count = 0
        for i in sorted(hits):
            text = d.lines[i]
            ranges = sorted({r for f in finders for r in f(text)})
            count += max(1, len(ranges))
            if len(lines) < limit_lines:
                lines.append({"line": i + 1, "text": text[:400], "ranges": [list(r) for r in ranges if r[0] < 400]})
        results.append({"rel": d.rel, "title": d.title, "count": count, "lines": lines, "more": max(0, len(hits) - limit_lines)})
    return {"results": results, "total": len(results), "explain": explain(node)}
