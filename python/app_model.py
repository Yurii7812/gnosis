#!/usr/bin/env python3
"""`\\A`（アプリ）の索引ナビ・索引ブラウザ・カレンダーが使うデータ（読み取り専用）。

ダブルインデックスを「辿れる形」にして返す:
  Global Index（index.md）の本文の項目 → 最初のノート → そのノートの BranchGroup: のトピック索引（グループ）
  → トピック索引の本文の項目 → ノート → …
項目の名前（索引語）は、置かれている索引によって意味が限定される（「ハーブ › 栽培」）。だから項目は
いつも「どの索引の、どの名前か」と一緒に返す。ノートも索引も書き換えない（書くのは Vim。`gnosis#app_op`）。

vault は一度読んだら覚えておき、次の問い合わせでは更新時刻と大きさが変わったファイルだけを読み直す。

使い方:
  app_model.py serve ROOT          1 行 1 つの JSON の問い合わせを標準入力から読み、1 行 1 つの JSON で答える
                                    {"id": 1, "method": "nav.note", "params": {"file": "x.md"}} → {"id": 1, "result": …}
  app_model.py call ROOT METHOD [JSON]   1 回だけ答える（試験・手で確かめる用）
"""
from __future__ import annotations

import calendar as _cal
import datetime as dt
import json
import os
import re
import sys
import time
import unicodedata
from collections import deque
from dataclasses import dataclass, field
from pathlib import Path
from urllib.parse import unquote

sys.path.insert(0, str(Path(__file__).resolve().parent))
import tasks as tk  # noqa: E402

LINK_RE = re.compile(r"(?<!!)\[((?:\\.|[^\]\\])*)\]\(([^)\s]+)(?:\s+\"[^\"]*\")?\)")
LINK_LINE_RE = re.compile(r"^\s*\[(?:\\.|[^\]\\])*\]\([^)\s]+\)\s*$")
GROUP_ATTR_RE = re.compile(r"^\s*(?:attribute|属性)\s*:\s*[\"']?(?:group|グループ|小グループ|カテゴリー|キーワード)[\"']?\s*$")
TOP_HEADS = {"BranchGroup:": "bg", "ThisNoteGroup:": "bg", "Group:": "groups", "ParentBranch:": "pb", "Context:": "ctx"}
BOTTOM_HEADS = {"ChildBranch:", "Related:", "BackLink:", "### Context", "### Parent", "### Group", "### Related", "### BackLink",
                "### ChildBranch", "### ParentBranch", "## Parent", "## Child"}
DIARY_TITLE_RE = re.compile(r"^(\d{4}-\d{2}-\d{2})-[A-Z]{2}-?$")
DATED_TITLE_RE = re.compile(r"^(\d{4}-\d{2}-\d{2})-[A-Z]{2}-(.+)$")   # 時系列記録のその日のノート（2026-10-19-MO-夢）
KANA_HEAD_RE = re.compile(r"^[ぁ-んァ-ヶA-Za-z0-9#＃他]$")


def _unesc(s: str) -> str:
    return re.sub(r"\\(.)", r"\1", s)


def norm(s: str) -> str:
    """検索用: 全角半角・大小文字・カタカナ/ひらがなの違いを無くす。"""
    s = unicodedata.normalize("NFKC", s).lower()
    return "".join(chr(ord(c) - 0x60) if "ァ" <= c <= "ヶ" else c for c in s)


@dataclass
class Link:
    text: str
    rel: str          # vault からの相対パス（解決できなければ ""）
    row: str = ""     # 本文の中で、直前にあった見出し・ラベル（索引の「あ」や「## 栽培」）
    line: int = 0     # 1 から


@dataclass
class Note:
    rel: str
    title: str
    is_group: bool = False
    fz: str = ""
    time: str = ""
    record: str = ""
    timeline: bool = False
    mandala: bool = False
    canvas: bool = False
    yomi: dict = field(default_factory=dict)
    bg: list = field(default_factory=list)       # BranchGroup:（トピック索引）
    groups: list = field(default_factory=list)   # Group:
    pb: list = field(default_factory=list)       # ParentBranch:
    ctx: list = field(default_factory=list)      # Context:
    body: list = field(default_factory=list)     # 本文のリンク（索引なら項目）
    preview: str = ""
    sig: tuple = ()


def _fence_flags(lines: list[str]) -> list[bool]:
    out, inside = [], False
    for ln in lines:
        if re.match(r"^\s*(```|~~~)", ln):
            out.append(True)
            inside = not inside
            continue
        out.append(inside)
    return out


def parse_note(root: Path, path: Path, text: str) -> Note:
    rel = path.relative_to(root).as_posix()
    lines = text.split("\n")
    fm: list[str] = []
    i = 0
    if lines and lines[0].strip() == "---":
        for j in range(1, len(lines)):
            if lines[j].strip() == "---":
                fm, i = lines[1:j], j + 1
                break
    n = Note(rel=rel, title=path.stem)
    in_yomi = False
    for ln in fm:
        if in_yomi and re.match(r"^\s+\S", ln):
            m = re.match(r'^\s+["\']?(.+?)["\']?\s*:\s*["\']?(.*?)["\']?\s*$', ln)
            if m:
                n.yomi[m.group(1)] = m.group(2)
            continue
        in_yomi = False
        m = re.match(r"^([\w-]+)\s*:\s*(.*?)\s*$", ln)
        if not m:
            continue
        k, v = m.group(1), m.group(2).strip().strip("\"'")
        if k == "title" and v:
            n.title = v
        elif k == "folgezettel":
            n.fz = v
        elif k == "time":
            n.time = v
        elif k == "record":
            n.record = v
        elif k == "timeline":
            n.timeline = v == "true"
        elif k == "mandala":
            n.mandala = v == "true"
        elif k == "canvas":
            n.canvas = v == "true"
        elif k == "yomi" and not v:
            in_yomi = True
        if GROUP_ATTR_RE.match(ln):
            n.is_group = True
    if rel == "index.md" or path.name == "index.md":
        n.is_group = True
    note_dir = path.parent
    flags = _fence_flags(lines)

    def resolve(target: str) -> str:
        t = unquote(target.split("#", 1)[0].strip())
        if not t or "://" in t or not t.lower().endswith(".md"):
            return ""
        p = os.path.normpath(note_dir / t)
        try:
            r = Path(p).relative_to(root).as_posix()
        except ValueError:
            return ""
        return r

    def links_in(ln: str, row: str, lnum: int) -> list[Link]:
        return [Link(_unesc(m.group(1)), resolve(m.group(2)), row, lnum) for m in LINK_RE.finditer(ln)]

    # H1 を探す
    h1 = -1
    for j in range(i, len(lines)):
        if not flags[j] and re.match(r"^#\s+\S", lines[j]):
            h1 = j
            break
    j = h1 + 1 if h1 >= 0 else i
    # 本文の上の先頭のブロック（BranchGroup: / Group: / ParentBranch: / Context:）
    while j < len(lines):
        s = lines[j].strip()
        if not s:
            # 空行のあとにまだ先頭のブロックが続くかを見る
            k = j
            while k < len(lines) and not lines[k].strip():
                k += 1
            if k < len(lines) and lines[k].strip() in TOP_HEADS:
                j = k
                continue
            break
        if s in TOP_HEADS and not flags[j]:
            kind = TOP_HEADS[s]
            j += 1
            while j < len(lines) and LINK_LINE_RE.match(lines[j]):
                getattr(n, kind).extend(links_in(lines[j], "", j + 1))
                j += 1
            continue
        break
    # 本文（下の節の見出しまで）
    row = ""
    for k in range(j, len(lines)):
        ln = lines[k]
        s = ln.strip()
        if flags[k]:
            continue
        if s in BOTTOM_HEADS:
            break
        if not s:
            continue
        found = links_in(ln, row, k + 1)
        if found:
            n.body.extend(found)
            continue
        hm = re.match(r"^#{1,6}\s+(.+?)\s*#*\s*$", s)
        if hm:
            row = hm.group(1)
        elif KANA_HEAD_RE.match(s) and n.is_group:
            row = s
        elif s.endswith((":", "：")) and len(s) <= 40:
            row = s[:-1]
        if not n.preview and not hm and not KANA_HEAD_RE.match(s) and not s.startswith("|"):
            n.preview = s[:120]
    return n


class Vault:
    def __init__(self, root: str | Path):
        self.root = Path(root).resolve()
        self.notes: dict[str, Note] = {}
        self._incoming: dict[str, list] | None = None
        self._links_in: dict[str, list] | None = None
        self._tasks: list | None = None
        self._bfs: dict | None = None
        self.refreshed_at = 0.0

    # ---- 読み込み（変わったファイルだけ） ----
    def refresh(self) -> int:
        seen = set()
        changed = 0
        for dirpath, dirnames, filenames in os.walk(self.root):
            dirnames[:] = [d for d in dirnames if not d.startswith(".")]
            for name in filenames:
                if not name.endswith(".md") or name.startswith("."):
                    continue
                p = Path(dirpath) / name
                rel = p.relative_to(self.root).as_posix()
                seen.add(rel)
                try:
                    st = p.stat()
                except OSError:
                    continue
                sig = (st.st_mtime_ns, st.st_size)
                old = self.notes.get(rel)
                if old is not None and old.sig == sig:
                    continue
                try:
                    text = p.read_text(encoding="utf-8")
                except (OSError, UnicodeDecodeError):
                    continue
                n = parse_note(self.root, p, text)
                n.sig = sig
                self.notes[rel] = n
                changed += 1
        for rel in [r for r in self.notes if r not in seen]:
            del self.notes[rel]
            changed += 1
        if changed:
            self._incoming = None
            self._links_in = None
            self._bfs = None
        self._tasks = None
        return changed

    def _rel_of(self, file: str) -> str:
        if not file:
            return ""
        p = Path(file)
        if p.is_absolute():
            try:
                return p.resolve().relative_to(self.root).as_posix()
            except ValueError:
                return ""
        return p.as_posix()

    def index_rel(self) -> str:
        if "index.md" in self.notes:
            return "index.md"
        return next((r for r in sorted(self.notes) if r.endswith("/index.md")), "")

    def incoming(self) -> dict[str, list]:
        """ノート → それを本文の項目に持つ索引（グループ）の [(索引, Link)]。"""
        if self._incoming is None:
            inc: dict[str, list] = {}
            for g in self.notes.values():
                if not g.is_group:
                    continue
                for lk in g.body:
                    if lk.rel and lk.rel != g.rel:
                        inc.setdefault(lk.rel, []).append((g.rel, lk))
            self._incoming = inc
        return self._incoming

    def ref(self, rel: str) -> dict:
        n = self.notes.get(rel)
        if n is None:
            return {"rel": rel, "title": Path(rel).stem, "missing": True}
        d = {"rel": rel, "title": n.title, "group": n.is_group}
        if n.fz:
            d["fz"] = n.fz
        return d

    def origin_of(self, grel: str) -> str:
        """トピック索引の起点のノート（BranchGroup: にこの索引を持つノート）。無ければ ""。"""
        g = self.notes.get(grel)
        cands = []
        for lk in (g.pb if g else []):
            o = self.notes.get(lk.rel)
            if o and any(b.rel == grel for b in o.bg):
                cands.append(lk.rel)
        if cands:
            return cands[0]
        for o in self.notes.values():
            if any(b.rel == grel for b in o.bg):
                return o.rel
        return ""

    # ---- 道（Index からの辿り方） ----
    def _tree(self) -> dict:
        """Global Index からの幅優先の木（ノート → (一つ前, via, label)）。vault が変わるまで覚えておく。
        辺: 索引 → 項目のノート（名前つき） / ノート → BranchGroup の索引。"""
        if self._bfs is None:
            start = self.index_rel()
            prev: dict[str, tuple] = {}
            if start:
                prev[start] = ("", "", "")
                dq = deque([start])
                while dq:
                    cur = dq.popleft()
                    n = self.notes.get(cur)
                    if n is None:
                        continue
                    nxt = []
                    if n.is_group:
                        nxt += [(lk.rel, "entry", lk.text) for lk in n.body if lk.rel]
                    nxt += [(lk.rel, "topic", lk.text) for lk in n.bg if lk.rel]
                    for r, via, label in nxt:
                        if r in self.notes and r not in prev:
                            prev[r] = (cur, via, label)
                            dq.append(r)
            self._bfs = prev
        return self._bfs

    def crumbs(self, rel: str, limit: int = 3) -> list[list[dict]]:
        """Global Index から rel までの、ダブルインデックスの道（索引の項目 → ノート → BranchGroup → 索引 …）。
        一番短いもの。各段は {rel, title, via: "entry"|"topic", label}。"""
        tree = self._tree()
        if rel not in tree:
            return []
        path = []
        cur = rel
        while cur:
            p, via, label = tree[cur]
            path.append({**self.ref(cur), "via": via, "label": label})
            cur = p
        return [list(reversed(path))][:limit]

    def parent_chain(self, rel: str, limit: int = 30) -> list[dict]:
        out, seen, cur = [], {rel}, rel
        while len(out) < limit:
            n = self.notes.get(cur)
            if n is None or not n.pb:
                break
            p = n.pb[0].rel
            if not p or p in seen:
                break
            seen.add(p)
            out.append(self.ref(p))
            cur = p
        return list(reversed(out))

    def path_text(self, rel: str) -> str:
        """索引の道を「Index › ハーブ › 栽培」の形の文字に。"""
        cs = self.crumbs(rel, 1)
        if not cs:
            return ""
        parts = []
        for st in cs[0]:
            if st["via"] == "topic":
                continue   # ノート → その索引 は同じ名前が続くので省く
            parts.append(st["label"] or st["title"])
        return " › ".join(parts)

    # ---- 1 つの索引（グループ）の項目 ----
    def entries(self, grel: str) -> list[dict]:
        g = self.notes.get(grel)
        if g is None:
            return []
        out = []
        for lk in g.body:
            if not lk.rel:
                continue
            t = self.notes.get(lk.rel)
            item = {"label": lk.text, "row": lk.row, "line": lk.line, **self.ref(lk.rel)}
            if t is not None:
                item["topics"] = len([b for b in t.bg if b.rel in self.notes])
                if t.is_group:
                    item["entries"] = len([x for x in t.body if x.rel])
            out.append(item)
        return out

    def topics(self, rel: str) -> list[dict]:
        n = self.notes.get(rel)
        if n is None:
            return []
        out = []
        for b in n.bg:
            if not b.rel:
                continue
            t = self.notes.get(b.rel)
            out.append({**self.ref(b.rel), "label": b.text, "entries": self.entries(b.rel) if t and t.is_group else []})
        return out

    # ---- ノート 1 つ分の索引の情報（索引ナビ） ----
    def note_info(self, file: str) -> dict:
        rel = self._rel_of(file)
        n = self.notes.get(rel)
        if n is None:
            return {"rel": rel, "missing": True}
        indexed = []
        for grel, lk in self.incoming().get(rel, []):
            origin = self.origin_of(grel)
            indexed.append({"index": self.ref(grel), "label": lk.text, "row": lk.row, "line": lk.line,
                            "origin": self.ref(origin) if origin else None, "path": self.path_text(grel)})
        indexed.sort(key=lambda x: (x["index"]["rel"] != self.index_rel(), x["path"]))
        d = {**self.ref(rel), "crumbs": self.crumbs(rel), "parents": self.parent_chain(rel), "indexed": indexed,
             "topics": self.topics(rel), "context": [self.ref(c.rel) for c in n.ctx if c.rel],
             "preview": n.preview, "is_index": rel == self.index_rel(), "kind": self.kind(n)}
        if n.is_group:
            d["entries"] = self.entries(rel)
            o = self.origin_of(rel)
            d["origin"] = self.ref(o) if o else None
        return d

    # ---- リンク（\\A の右のバー: バックリンク・出ていくリンク・関係） ----
    LINK_PLACES = (("body", "本文"), ("ctx", "Context"), ("pb", "ParentBranch"), ("groups", "Group"), ("bg", "BranchGroup"))

    def links_in(self) -> dict[str, list]:
        """ノート → それへリンクしている (ノート, 場所, Link) の一覧（本文と先頭のブロック。下の BackLink: などの節は数えない）。"""
        if self._links_in is None:
            inc: dict[str, list] = {}
            for m in self.notes.values():
                for attr, place in self.LINK_PLACES:
                    for lk in getattr(m, attr):
                        if lk.rel and lk.rel != m.rel:
                            inc.setdefault(lk.rel, []).append((m.rel, place, lk))
            self._links_in = inc
        return self._links_in

    def links(self, file: str) -> dict:
        rel = self._rel_of(file)
        n = self.notes.get(rel)
        if n is None:
            return {"rel": rel, "missing": True}
        back: dict[str, dict] = {}
        for src, place, lk in self.links_in().get(rel, []):
            b = back.setdefault(src, {**self.ref(src), "kind": self.kind(self.notes[src]), "places": [], "hits": []})
            if place not in b["places"]:
                b["places"].append(place)
            if len(b["hits"]) < 5:
                b["hits"].append({"place": place, "text": lk.text, "row": lk.row, "line": lk.line})
        backs = sorted(back.values(), key=lambda x: (x["places"] == ["Group"], x["title"]))
        out, seen = [], set()
        for lk in n.body:
            key = lk.rel or ("?" + lk.text)
            if key in seen:
                continue
            seen.add(key)
            out.append({**(self.ref(lk.rel) if lk.rel else {"rel": "", "title": lk.text, "missing": True}), "text": lk.text, "line": lk.line})
        children = [self.ref(m.rel) for m in self.notes.values() if any(lk.rel == rel for lk in m.pb)]
        refs = lambda lst: [self.ref(lk.rel) for lk in lst if lk.rel]
        return {**self.ref(rel), "kind": self.kind(n), "backlinks": backs, "outgoing": out,
                "context": refs(n.ctx), "parents": refs(n.pb), "children": sorted(children, key=lambda x: (x.get("fz", ""), x["title"])),
                "groups": refs(n.groups), "topics": refs(n.bg)}

    def kind(self, n: Note) -> str:
        if n.rel == self.index_rel():
            return "index"
        if n.mandala:
            return "mandala"
        if n.canvas:
            return "canvas"
        if n.is_group:
            return "topic" if self.origin_of(n.rel) else "group"
        if DIARY_TITLE_RE.match(n.title):
            return "diary"
        return "note"

    # ---- 索引語で探す ----
    def search(self, q: str, limit: int = 60) -> list[dict]:
        qn = norm(q.strip())
        if not qn:
            return []
        hits = []
        seen = set()
        for g in self.notes.values():
            if not g.is_group:
                continue
            for lk in g.body:
                if not lk.rel:
                    continue
                t = self.notes.get(lk.rel)
                yomi = norm((t.yomi.get(lk.text, "") if t else ""))
                lab = norm(lk.text)
                score = 0 if lab == qn or yomi == qn else 1 if lab.startswith(qn) or (yomi and yomi.startswith(qn)) else 2 if qn in lab or (yomi and qn in yomi) else -1
                if score < 0:
                    continue
                key = (g.rel, lk.rel, lk.text)
                if key in seen:
                    continue
                seen.add(key)
                hits.append((score, 0, {"kind": "entry", "label": lk.text, "target": self.ref(lk.rel), "index": self.ref(g.rel),
                                        "path": self.path_text(g.rel), "row": lk.row}))
        for n in self.notes.values():
            tn = norm(n.title)
            if qn in tn:
                hits.append((0 if tn == qn else 1 if tn.startswith(qn) else 2, 1, {"kind": "title", "label": n.title, "target": self.ref(n.rel),
                                                                                    "path": self.path_text(n.rel)}))
        hits.sort(key=lambda h: (h[0], h[1], len(h[2]["label"]), h[2]["path"]))
        return [h[2] for h in hits[:limit]]

    def unindexed(self, limit: int = 200) -> list[dict]:
        """Global Index から辿れないノート（索引にまだ載っていないもの）。新しい順。日記・時系列記録・その日のノートは除く。"""
        tree = self._tree()
        out = []
        for n in self.notes.values():
            if n.rel in tree or n.timeline or n.record or DIARY_TITLE_RE.match(n.title) or DATED_TITLE_RE.match(n.title):
                continue
            out.append({**self.ref(n.rel), "time": n.time, "kind": self.kind(n), "preview": n.preview})
        out.sort(key=lambda x: x["time"] or "", reverse=True)
        return out[:limit]

    def indexes(self) -> list[dict]:
        """載せ先に選べる索引（グループ）の一覧。Global Index が先頭、その後は道の文字の順。"""
        out = []
        for g in self.notes.values():
            if not g.is_group or g.timeline:
                continue
            o = self.origin_of(g.rel)
            out.append({**self.ref(g.rel), "origin": self.ref(o) if o else None, "path": self.path_text(g.rel) or g.title,
                        "count": len([x for x in g.body if x.rel]), "is_index": g.rel == self.index_rel()})
        out.sort(key=lambda x: (not x["is_index"], x["path"]))
        return out

    def notes_list(self, q: str = "", limit: int = 80, kind: str = "") -> list[dict]:
        qn = norm(q)
        out = []
        for n in self.notes.values():
            if qn and qn not in norm(n.title) and qn not in norm(n.rel):
                continue
            if kind and self.kind(n) != kind:
                continue
            out.append({**self.ref(n.rel), "time": n.time, "kind": self.kind(n)})
        out.sort(key=lambda x: (x["time"] or ""), reverse=True)
        out = out[:limit]
        for x in out:
            x["path"] = self.path_text(x["rel"])   # 同じ題のノート（最初のノートとそのトピック索引など）を見分ける
        return out

    # ---- カレンダー ----
    def _day_of(self, n: Note) -> str:
        m = DIARY_TITLE_RE.match(n.title) or DATED_TITLE_RE.match(n.title)
        return m.group(1) if m else ""

    def month(self, ym: str) -> dict:
        y, m = (int(x) for x in ym.split("-"))
        last = _cal.monthrange(y, m)[1]
        a, b = f"{y:04d}-{m:02d}-01", f"{y:04d}-{m:02d}-{last:02d}"
        days: dict[str, dict] = {f"{y:04d}-{m:02d}-{d:02d}": {"diary": None, "records": [], "created": 0, "due": [], "done": 0} for d in range(1, last + 1)}
        for n in self.notes.values():
            day = self._day_of(n)
            if day and a <= day <= b:
                if DIARY_TITLE_RE.match(n.title) and not n.record:
                    days[day]["diary"] = {**self.ref(n.rel), "preview": n.preview}
                else:
                    dm = DATED_TITLE_RE.match(n.title)
                    days[day]["records"].append({**self.ref(n.rel), "record": n.record or (dm.group(2) if dm else "")})
            created = n.time[:10]
            if created and a <= created <= b and not day and not n.is_group and not n.timeline:
                days[created]["created"] += 1
        for t in self.tasks():
            if not t.done and t.due and a <= t.due <= b:
                days[t.due]["due"].append(self._task(t))
            elif not t.done and t.scheduled and a <= t.scheduled <= b:
                days[t.scheduled]["due"].append(self._task(t))
            if t.done and t.done_date and a <= t.done_date <= b:
                days[t.done_date]["done"] += 1
        for v in days.values():
            v["due"].sort(key=lambda x: (x["time"] or "99:99", x["text"]))
        return {"ym": f"{y:04d}-{m:02d}", "today": dt.date.today().isoformat(), "days": days}

    def tasks(self) -> list:
        # タスクは本文の行そのものなので、tasks.py と同じ解析で読む（1 回の問い合わせの中では使い回す）
        if self._tasks is None:
            self._tasks = tk.collect(self.root)
        return self._tasks

    def _task(self, t) -> dict:
        n = self.notes.get(t.file)
        return {"file": t.file, "line": t.line, "text": t.text, "done": t.done, "due": t.due or t.scheduled, "time": t.due_time,
                "priority": t.priority, "repeat": t.repeat, "note": n.title if n else Path(t.file).stem, "done_date": t.done_date}

    def day(self, date: str) -> dict:
        dt.date.fromisoformat(date)
        created, records, diary = [], [], None
        for n in self.notes.values():
            d = self._day_of(n)
            if d == date:
                if DIARY_TITLE_RE.match(n.title) and not n.record:
                    diary = {**self.ref(n.rel), "preview": n.preview}
                else:
                    records.append(self.ref(n.rel))
            elif n.time[:10] == date and not n.is_group and not n.timeline:
                created.append({**self.ref(n.rel), "time": n.time[11:16], "path": self.path_text(n.rel)})
        created.sort(key=lambda x: x["time"])
        due, done = [], []
        for t in self.tasks():
            if not t.done and (t.due == date or (not t.due and t.scheduled == date)):
                due.append(self._task(t))
            if t.done and t.done_date == date:
                done.append(self._task(t))
        due.sort(key=lambda x: (x["time"] or "99:99", x["text"]))
        overdue = []
        if date == dt.date.today().isoformat():
            overdue = sorted((self._task(t) for t in self.tasks() if not t.done and (t.due or t.scheduled) and (t.due or t.scheduled) < date),
                             key=lambda x: x["due"])
        return {"date": date, "diary": diary, "records": records, "created": created, "due": due, "done": done, "overdue": overdue,
                "today": dt.date.today().isoformat()}


def task_complete_text(vault: Vault, file: str, line: int, today: str = "") -> dict:
    """タスクを完了にした後の本文を返す（書かない。書くのは Vim）。"""
    rel = vault._rel_of(file)
    p = vault.root / rel
    text = p.read_text(encoding="utf-8")
    new, res = tk.complete_text(text, int(line), dt.date.fromisoformat(today) if today else dt.date.today())
    return {**res, "file": str(p), "text": new}


METHODS = {
    "nav.note": lambda v, p: v.note_info(p.get("file", "")),
    "nav.search": lambda v, p: v.search(p.get("q", "")),
    "nav.topics": lambda v, p: v.topics(v._rel_of(p.get("file", ""))),
    "nav.entries": lambda v, p: v.entries(v._rel_of(p.get("file", ""))),
    "nav.indexes": lambda v, p: v.indexes(),
    "nav.notes": lambda v, p: v.notes_list(p.get("q", ""), limit=max(1, min(int(p.get("limit", 80) or 80), 2000)), kind=p.get("kind", "")),
    "nav.root": lambda v, p: v.note_info(v.index_rel()),
    "nav.unindexed": lambda v, p: v.unindexed(),
    "nav.links": lambda v, p: v.links(p.get("file", "")),
    "cal.month": lambda v, p: v.month(p.get("ym") or dt.date.today().strftime("%Y-%m")),
    "cal.day": lambda v, p: v.day(p.get("date") or dt.date.today().isoformat()),
    "task.complete": lambda v, p: task_complete_text(v, p.get("file", ""), p.get("line", 0), p.get("today", "")),
}


# 打つたびに来る問い合わせ（探す）は、vault の読み直しを 1.5 秒に 1 回へ間引く（1 万ノートで 1 回 0.2 秒ほど）
LIGHT = {"nav.search", "nav.notes", "nav.indexes"}


def handle(vault: Vault, req: dict) -> dict:
    rid = req.get("id")
    try:
        method = req.get("method", "")
        fn = METHODS.get(method)
        if fn is None:
            return {"id": rid, "error": "知らない問い合わせです: " + str(method)}
        now = time.monotonic()
        if method not in LIGHT or now - vault.refreshed_at > 1.5:
            vault.refresh()
            vault.refreshed_at = now
        return {"id": rid, "result": fn(vault, req.get("params") or {})}
    except (OSError, ValueError, KeyError, TypeError) as e:
        return {"id": rid, "error": str(e) or e.__class__.__name__}


def serve(root: str) -> int:
    vault = Vault(root)
    vault.refresh()
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            req = json.loads(line)
        except json.JSONDecodeError:
            continue
        sys.stdout.write(json.dumps(handle(vault, req), ensure_ascii=False) + "\n")
        sys.stdout.flush()
    return 0


def main(argv: list[str]) -> int:
    if len(argv) >= 2 and argv[0] == "serve":
        return serve(argv[1])
    if len(argv) >= 3 and argv[0] == "call":
        v = Vault(argv[1])
        r = handle(v, {"id": 0, "method": argv[2], "params": json.loads(argv[3]) if len(argv) > 3 else {}})
        print(json.dumps(r, ensure_ascii=False, indent=1))
        return 0 if "error" not in r else 1
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
